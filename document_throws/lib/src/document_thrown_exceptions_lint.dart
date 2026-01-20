import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'document_thrown_exceptions_collection.dart';
import 'documentation_style.dart';
import 'throwing_doc_parser.dart';
import 'throws_cache_lookup.dart';

class DocumentThrownExceptions extends MultiAnalysisRule {
  static const LintCode code = LintCode(
    'document_thrown_exceptions',
    'Document thrown exception types with @Throwing. Missing: {0}.',
    correctionMessage:
        'Add @Throwing(<ExceptionType>) in docs or annotations for each thrown '
        'exception class.',
  );
  static const LintCode malformedDocCode = LintCode(
    'malformed_exception_documentation',
    'Malformed @Throwing doc comment: {0}',
    correctionMessage: 'Use @Throwing(<ExceptionType>, ...) in doc comments.',
  );
  static const LintCode docMentionCode = LintCode(
    'unthrown_exceptions_documented',
    'Doc comment mentions exception types that are not thrown: {0}.',
    correctionMessage: 'Remove mentions for exceptions not thrown.',
  );

  // Configure the lint rule metadata.
  DocumentThrownExceptions()
    : super(
        name: code.name,
        description:
            'Require @Throwing documentation for each exception class thrown '
            'by a method.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => [
    code,
    malformedDocCode,
    docMentionCode,
  ];

  @override
  // Register visitors that inspect executable members.
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addConstructorDeclaration(this, visitor)
      ..addFunctionDeclaration(this, visitor)
      ..addMethodDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final DocumentThrownExceptions rule;
  final RuleContext context;
  final Map<String, CompilationUnit> unitsByPath;
  final ThrowsCacheLookup? externalLookup;
  final DocumentationStyle documentationStyle;

  // Hold the rule to report diagnostics.
  _Visitor(this.rule, this.context)
    : unitsByPath = _unitsByPathFromContext(context),
      externalLookup = _throwsCacheLookupFromContext(context),
      documentationStyle = documentationStyleForContext(context);

  @override
  // Inspect method bodies for undocumented throw types.
  void visitMethodDeclaration(MethodDeclaration node) {
    _checkExecutable(
      body: node.body,
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      reportToken: node.name,
    );
  }

  @override
  // Inspect constructor bodies for undocumented throw types.
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _checkExecutable(
      body: node.body,
      metadata: node.metadata,
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
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      reportToken: node.name,
    );
  }

  void _checkExecutable({
    required FunctionBody body,
    required NodeList<Annotation>? metadata,
    required Comment? documentationComment,
    required Token reportToken,
  }) {
    // Fast exit when no throw token appears in the body.
    if (body is EmptyFunctionBody) return;

    final thrownResults = thrownTypeAnalyzer.collectThrownTypes(
      body,
      unitsByPath: unitsByPath,
      externalLookup: externalLookup,
    );

    if (documentationStyle == DocumentationStyle.docComment &&
        documentationComment != null) {
      final parsed = parseThrowingDocComment(documentationComment);
      for (final error in parsed.errors) {
        rule.reportAtToken(
          reportToken,
          diagnosticCode: DocumentThrownExceptions.malformedDocCode,
          arguments: [error.message],
        );
      }
    }

    // Report when any thrown types are missing from docs.
    final missing = missingThrownTypeDocs(
      body,
      metadata,
      documentationComment: documentationComment,
      documentationStyle: documentationStyle,
      honorDocMentions: false,
      unitsByPath: unitsByPath,
      externalLookup: externalLookup,
      thrownResults: thrownResults,
    );
    if (missing.isEmpty) return;

    final missingList = missing.toList()..sort();
    final missingLabel = missingList.join(', ');
    rule.reportAtToken(
      reportToken,
      diagnosticCode: DocumentThrownExceptions.code,
      arguments: [missingLabel],
    );
  }
}

Map<String, CompilationUnit> _unitsByPathFromContext(RuleContext context) {
  final map = <String, CompilationUnit>{};
  for (final unit in context.allUnits) {
    map[unit.file.path] = unit.unit;
  }
  return map;
}

ThrowsCacheLookup? _throwsCacheLookupFromContext(RuleContext context) {
  final root = context.package?.root.path;
  if (root == null) return null;
  return ThrowsCacheLookup.forProjectRoot(root);
}
