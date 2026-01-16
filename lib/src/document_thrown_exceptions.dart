import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
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
_ThrownTypeResults _collectThrownTypes(FunctionBody body) {
  final collector = _ThrowTypeCollector();
  body.accept(collector);
  return _ThrownTypeResults(
    collector.thrownTypes,
    sawThrowExpression: collector.sawThrowExpression,
    sawUnknownThrowExpression: collector.sawUnknownThrowExpression,
  );
}

class _ThrownTypeResults {
  final Set<String> types;
  final bool sawThrowExpression;
  final bool sawUnknownThrowExpression;

  const _ThrownTypeResults(
    this.types, {
    required this.sawThrowExpression,
    required this.sawUnknownThrowExpression,
  });
}

// Find thrown types missing from documentation.
Set<String> missingThrownTypeDocs(
  FunctionBody body,
  Comment? documentationComment, {
  bool allowSourceFallback = false,
}) {
  // Prefer AST; optionally fallback to source parsing for edge cases.
  final thrownResults = _collectThrownTypes(body);
  final thrownTypes = thrownResults.types;
  if (thrownTypes.isEmpty &&
      allowSourceFallback &&
      (thrownResults.sawUnknownThrowExpression ||
          !thrownResults.sawThrowExpression)) {
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
  final matches = RegExp(r'\bthrow\s+([A-Z][A-Za-z0-9_]*)').allMatches(source);
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

class _ThrownTypeInfo {
  final String name;
  final DartType? type;

  const _ThrownTypeInfo(this.name, this.type);
}

class _ThrowTypeCollector extends RecursiveAstVisitor<void> {
  final List<_ThrownTypeInfo> _thrown = [];
  final Set<String> thrownTypes = <String>{};
  bool sawThrowExpression = false;
  int _unknownThrowCount = 0;

  _ThrowTypeCollector();

  bool get sawUnknownThrowExpression => _unknownThrowCount > 0;

  @override
  // Record exception types from throw expressions.
  void visitThrowExpression(ThrowExpression node) {
    sawThrowExpression = true;
    final info = _thrownTypeFromExpression(node.expression);
    if (info != null) {
      _recordThrow(info);
    } else {
      _unknownThrowCount++;
    }
    super.visitThrowExpression(node);
  }

  @override
  // Skip throws caught by a try/catch without rethrowing.
  void visitTryStatement(TryStatement node) {
    final bodyCollector = _ThrowTypeCollector();
    node.body.accept(bodyCollector);

    for (final info in bodyCollector._thrown) {
      if (!_isCaughtWithoutRethrow(info, node.catchClauses)) {
        _recordThrow(info);
      }
    }

    if (bodyCollector.sawThrowExpression) {
      sawThrowExpression = true;
    }
    if (bodyCollector._unknownThrowCount > 0 &&
        !_catchesAllWithoutRethrow(node.catchClauses)) {
      _unknownThrowCount += bodyCollector._unknownThrowCount;
    }

    for (final clause in node.catchClauses) {
      clause.body.accept(this);
    }
    node.finallyBlock?.accept(this);
  }

  void _recordThrow(_ThrownTypeInfo info) {
    _thrown.add(info);
    thrownTypes.add(info.name);
  }

  bool _isCaughtWithoutRethrow(
    _ThrownTypeInfo info,
    NodeList<CatchClause> catchClauses,
  ) {
    for (final clause in catchClauses) {
      if (_catchMatches(info, clause)) {
        return !_catchRethrows(clause);
      }
    }
    return false;
  }

  bool _catchMatches(_ThrownTypeInfo info, CatchClause clause) {
    final exceptionType = clause.exceptionType;
    if (exceptionType == null) return true;

    final catchType = exceptionType.type;
    if (catchType != null && info.type != null) {
      if (_isSubtypeOf(info.type!, catchType)) return true;
    }

    final catchName = _catchTypeName(exceptionType);
    if (catchName == null) return false;
    if (_isCatchAllName(catchName, info.name)) return true;
    if (catchName == info.name) return true;
    return false;
  }

  bool _isSubtypeOf(DartType thrownType, DartType catchType) {
    if (thrownType is InterfaceType && catchType is InterfaceType) {
      if (thrownType.element == catchType.element) return true;
      for (final supertype in thrownType.allSupertypes) {
        if (supertype.element == catchType.element) return true;
      }
    }
    return false;
  }

  bool _catchRethrows(CatchClause clause) {
    final finder = _RethrowFinder();
    clause.body.accept(finder);
    return finder.found;
  }

  bool _catchesAllWithoutRethrow(NodeList<CatchClause> catchClauses) {
    for (final clause in catchClauses) {
      if (_catchRethrows(clause)) continue;
      final exceptionType = clause.exceptionType;
      if (exceptionType == null) return true;
      final catchName = _normalizeCatchTypeName(exceptionType.toSource());
      if (catchName == null) continue;
      if (catchName == 'Object' ||
          catchName == 'dynamic' ||
          catchName == 'Exception' ||
          catchName == 'Error') {
        return true;
      }
    }
    return false;
  }
}

class _RethrowFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitRethrowExpression(RethrowExpression node) {
    found = true;
  }
}

// Normalize a thrown expression into a type name and type, if available.
_ThrownTypeInfo? _thrownTypeFromExpression(Expression expression) {
  if (expression is InstanceCreationExpression) {
    final typeName = expression.constructorName.type.name.lexeme;
    final normalized = _normalizeTypeName(typeName);
    if (normalized == null) return null;
    return _ThrownTypeInfo(normalized, expression.staticType);
  }

  final staticType = expression.staticType;
  if (staticType == null) return null;

  final displayName = staticType.getDisplayString();
  final normalized = _normalizeTypeName(displayName);
  if (normalized == null) return null;
  return _ThrownTypeInfo(normalized, staticType);
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

String? _normalizeCatchTypeName(String rawName) {
  var name = rawName.trim();
  if (name.isEmpty) return null;

  name = name.split(RegExp(r'\s+')).first;

  if (name.endsWith('?')) {
    name = name.substring(0, name.length - 1);
  }

  final genericSplit = name.split('<');
  name = genericSplit.first;

  final dotIndex = name.lastIndexOf('.');
  if (dotIndex != -1) {
    name = name.substring(dotIndex + 1);
  }

  return name;
}

String? _catchTypeName(TypeAnnotation exceptionType) {
  if (exceptionType is NamedType) {
    return _normalizeCatchTypeName(exceptionType.name.lexeme);
  }
  return _normalizeCatchTypeName(exceptionType.toSource());
}

bool _isCatchAllName(String catchName, String thrownName) {
  if (catchName == 'Object' || catchName == 'dynamic') return true;
  if (catchName == 'Exception') return thrownName.endsWith('Exception');
  if (catchName == 'Error') return thrownName.endsWith('Error');
  return false;
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
