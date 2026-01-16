import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

class DocumentThrownExceptions extends AnalysisRule {
  static const LintCode code = LintCode(
    'document_thrown_exceptions',
    'Document thrown exception types in method docs.',
    correctionMessage:
        'Add "Throws [ExceptionType]" in the method documentation for each '
        'thrown exception class.',
  );

  // Configure the lint rule metadata.
  DocumentThrownExceptions()
      : super(
          name: code.name,
          description:
              'Require documentation of each exception class thrown by a '
              'method.',
        );

  @override
  // Expose lint code for registration and fixes.
  LintCode get diagnosticCode => code;

  @override
  // Register visitors that inspect executable members.
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry
      ..addConstructorDeclaration(this, visitor)
      ..addFunctionDeclaration(this, visitor)
      ..addMethodDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  // Hold the rule to report diagnostics.
  _Visitor(this.rule);

  @override
  // Inspect method bodies for undocumented throw types.
  void visitMethodDeclaration(MethodDeclaration node) {
    _checkExecutable(
      body: node.body,
      documentationComment: node.documentationComment,
      reportToken: node.name,
    );
  }

  @override
  // Inspect constructor bodies for undocumented throw types.
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _checkExecutable(
      body: node.body,
      documentationComment: node.documentationComment,
      reportToken: node.returnType.beginToken,
    );
  }

  @override
  // Inspect top-level functions only (skip local/anonymous).
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is! CompilationUnit) return;
    _checkExecutable(
      body: node.functionExpression.body,
      documentationComment: node.documentationComment,
      reportToken: node.name,
    );
  }

  void _checkExecutable({
    required FunctionBody body,
    required Comment? documentationComment,
    required Token reportToken,
  }) {
    // Fast exit when no throw token appears in the body.
    if (body is EmptyFunctionBody) return;
    if (!_containsThrowToken(body)) return;

    // Report when any thrown types are missing from docs.
    final missing = missingThrownTypeDocs(body, documentationComment);
    if (missing.isEmpty) return;

    rule.reportAtToken(reportToken);
  }
}

// Collect thrown exception types via AST traversal.
Set<String> _collectThrownTypes(FunctionBody body) {
  final collector = _ThrowTypeCollector();
  body.accept(collector);
  return collector.thrownTypes;
}

// Find thrown types missing from documentation.
Set<String> missingThrownTypeDocs(
  FunctionBody body,
  Comment? documentationComment, {
  bool allowSourceFallback = false,
}
) {
  // Prefer AST; optionally fallback to source parsing for edge cases.
  final thrownTypes = _collectThrownTypes(body);
  if (thrownTypes.isEmpty && allowSourceFallback) {
    thrownTypes.addAll(_collectThrownTypesFromSource(body.toSource()));
  }
  if (thrownTypes.isEmpty) return <String>{};

  final docText =
      documentationComment == null ? '' : _docText(documentationComment);
  final missing = thrownTypes.where((t) => !_docMentionsType(docText, t));
  return missing.toSet();
}

// Join all comment tokens into a searchable string.
String _docText(Comment comment) {
  final buffer = StringBuffer();
  for (final token in comment.tokens) {
    buffer.writeln(token.lexeme);
  }
  return buffer.toString();
}

// Extract thrown types from source text as a fallback.
Set<String> _collectThrownTypesFromSource(String source) {
  final matches =
      RegExp(r'\bthrow\s+([A-Z][A-Za-z0-9_]*)').allMatches(source);
  final types = <String>{};
  for (final match in matches) {
    final name = match.group(1);
    final normalized = name == null ? null : _normalizeTypeName(name);
    if (normalized != null) {
      types.add(normalized);
    }
  }
  return types;
}

// Check for doc links, @throws tags, or "throws" clauses.
bool _docMentionsType(String docText, String typeName) {
  if (docText.contains('[$typeName]')) return true;
  final lower = docText.toLowerCase();
  if (lower.contains('@throws ${typeName.toLowerCase()}')) return true;

  final normalizedType = _normalizeDocType(typeName);
  final throwClause = RegExp(
    r'\bthrows?\b(?:\s+\w+)?(.*?)(?:[.!?]|$)',
    caseSensitive: false,
    dotAll: true,
  );
  final bracketedType = RegExp(r'\[([^\]]+)\]');

  for (final match in throwClause.allMatches(docText)) {
    final clause = match.group(1) ?? '';
    for (final typeMatch in bracketedType.allMatches(clause)) {
      final docType = _normalizeDocType(typeMatch.group(1) ?? '');
      if (docType == normalizedType) return true;
    }
  }

  return false;
}

// Normalize doc types for comparisons across spacing/casing differences.
String _normalizeDocType(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty) return '';
  return name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

class _ThrowTypeCollector extends RecursiveAstVisitor<void> {
  final Set<String> thrownTypes = <String>{};

  @override
  // Record exception types from throw expressions.
  void visitThrowExpression(ThrowExpression node) {
    final typeName = _typeNameFromExpression(node.expression);
    if (typeName != null) {
      thrownTypes.add(typeName);
    }
    super.visitThrowExpression(node);
  }
}

// Normalize a thrown expression into a type name, if available.
String? _typeNameFromExpression(Expression expression) {
  if (expression is InstanceCreationExpression) {
    final typeName = expression.constructorName.type.name.lexeme;
    return _normalizeTypeName(typeName);
  }

  final staticType = expression.staticType;
  if (staticType == null) return null;

  final displayName = staticType.getDisplayString();
  return _normalizeTypeName(displayName);
}

// Strip generics/qualifiers and drop non-specific types.
String? _normalizeTypeName(String rawName) {
  var name = rawName.trim();
  if (name.isEmpty) return null;

  final genericSplit = name.split('<');
  name = genericSplit.first;

  final dotIndex = name.lastIndexOf('.');
  if (dotIndex != -1) {
    name = name.substring(dotIndex + 1);
  }

  if (name == 'dynamic' || name == 'Object' || name == 'Never') return null;
  return name;
}

// Scan tokens to quickly see if a throw exists at all.
bool _containsThrowToken(FunctionBody body) {
  var token = body.beginToken;
  final end = body.endToken;
  while (true) {
    if (token.keyword == Keyword.THROW) return true;
    if (identical(token, end)) break;
    token = token.next!;
  }
  return false;
}
