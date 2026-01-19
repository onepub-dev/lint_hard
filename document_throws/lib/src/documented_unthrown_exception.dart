import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'document_thrown_exceptions.dart';
import 'throwing_annotation.dart';
import 'throwing_doc_parser.dart';
import 'throws_cache_lookup.dart';

class ThrowingUnthrownException extends AnalysisRule {
  static const LintCode code = LintCode(
    'documented_unthrown_exception',
    'Documented @Throwing exception type: {0}.',
    correctionMessage: 'Remove @Throwing types that are not thrown.',
  );

  ThrowingUnthrownException()
    : super(
        name: code.name,
        description:
            'Warn when @Throwing documents exception types that are not '
            'thrown by the executable.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
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
  final AnalysisRule rule;
  final Map<String, CompilationUnit> unitsByPath;
  final ThrowsCacheLookup? externalLookup;

  _Visitor(this.rule, RuleContext context)
    : unitsByPath = _unitsByPathFromContext(context),
      externalLookup = _throwsCacheLookupFromContext(context);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _checkExecutable(
      body: node.body,
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      reportToken: node.name,
    );
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _checkExecutable(
      body: node.body,
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      reportToken: node.returnType.beginToken,
    );
  }

  @override
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
    final thrown = collectThrownTypeNames(
      body,
      unitsByPath: unitsByPath,
      externalLookup: externalLookup,
    );
    if (thrown.isEmpty) return;

    final documented = <String>{};
    documented.addAll(_docCommentThrownTypes(documentationComment));
    documented.addAll(_annotationThrownTypes(metadata));
    for (final typeName in documented) {
      if (!thrown.contains(typeName)) {
        rule.reportAtToken(reportToken, arguments: [typeName]);
      }
    }
  }
}

Set<String> _docCommentThrownTypes(Comment? comment) {
  final parsed = parseThrowingDocComment(comment);
  if (parsed.typeNames.isEmpty) return const <String>{};
  final types = <String>{};
  for (final rawType in parsed.typeNames) {
    final normalized = _normalizeTypeName(rawType);
    if (normalized != null) {
      types.add(normalized);
    }
  }
  return types;
}

Set<String> _annotationThrownTypes(NodeList<Annotation>? metadata) {
  if (metadata == null || metadata.isEmpty) return const <String>{};
  final types = <String>{};
  for (final annotation in metadata) {
    if (!_isThrowingAnnotation(annotation)) continue;
    final args = annotation.arguments?.arguments;
    if (args == null || args.isEmpty) continue;
    final normalized = _normalizeTypeName(args.first.toSource());
    if (normalized != null) {
      types.add(normalized);
    }
  }
  return types;
}

bool _isThrowingAnnotation(Annotation annotation) {
  final name = annotation.name;
  if (name is SimpleIdentifier) return name.name == throwingAnnotationName;
  if (name is PrefixedIdentifier) {
    return name.identifier.name == throwingAnnotationName;
  }
  return false;
}

String? _normalizeTypeName(String rawName) {
  var name = rawName.trim();
  if (name.isEmpty) return null;

  if (name.startsWith('const ')) {
    name = name.substring(6).trimLeft();
  }

  final genericSplit = name.split('<');
  name = genericSplit.first;

  final dotIndex = name.lastIndexOf('.');
  if (dotIndex != -1) {
    name = name.substring(dotIndex + 1);
  }

  if (name.endsWith('?')) {
    name = name.substring(0, name.length - 1);
  }

  if (name == 'dynamic' || name == 'Object' || name == 'Never') return null;
  return name;
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
