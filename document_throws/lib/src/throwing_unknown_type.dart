import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'throwing_annotation.dart';
import 'throwing_doc_parser.dart';

class ThrowingUnknownType extends AnalysisRule {
  static const LintCode code = LintCode(
    'throwing_unknown_type',
    'Unknown @Throwing exception type: {0}.',
    correctionMessage: 'Use a known exception type or fix the import.',
  );

  ThrowingUnknownType()
    : super(
        name: code.name,
        description:
            'Warn when @Throwing references an exception type that '
            'does not exist in the current library scope.',
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
  final LibraryElement? library;

  _Visitor(this.rule, RuleContext context) : library = context.libraryElement;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _checkExecutable(
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      reportToken: node.name,
    );
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _checkExecutable(
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      reportToken: node.returnType.beginToken,
    );
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is! CompilationUnit) return;
    _checkExecutable(
      metadata: node.metadata,
      documentationComment: node.documentationComment,
      reportToken: node.name,
    );
  }

  void _checkExecutable({
    required NodeList<Annotation>? metadata,
    required Comment? documentationComment,
    required Token reportToken,
  }) {
    if (library == null) return;
    _checkDocComments(documentationComment, reportToken);
    _checkAnnotations(metadata, reportToken);
  }

  void _checkDocComments(Comment? comment, Token reportToken) {
    if (comment == null) return;
    final parsed = parseThrowingDocComment(comment);
    for (final rawType in parsed.typeNames) {
      final reference = _parseDocTypeReference(rawType);
      if (reference == null) continue;
      final resolved = _resolveTypeReference(reference);
      if (resolved == null) {
        rule.reportAtToken(
          reportToken,
          arguments: [reference.displayName],
        );
      }
    }
  }

  void _checkAnnotations(NodeList<Annotation>? metadata, Token reportToken) {
    if (metadata == null || metadata.isEmpty) return;
    for (final annotation in metadata) {
      if (!_isThrowingAnnotation(annotation)) continue;
      final expression = _throwingAnnotationArgument(annotation);
      if (expression == null) continue;
      final element = _typeElementFromExpression(expression);
      if (element == null || !_isTypeElement(element)) {
        final name = _annotationArgumentLabel(expression);
        rule.reportAtToken(reportToken, arguments: [name ?? 'unknown']);
      }
    }
  }

  bool _isThrowingAnnotation(Annotation annotation) {
    final name = annotation.name;
    if (name is SimpleIdentifier) return name.name == throwingAnnotationName;
    if (name is PrefixedIdentifier) {
      return name.identifier.name == throwingAnnotationName;
    }
    return false;
  }

  Expression? _throwingAnnotationArgument(Annotation annotation) {
    final args = annotation.arguments?.arguments;
    if (args == null || args.isEmpty) return null;
    return args.first;
  }

  String? _annotationArgumentLabel(Expression expression) {
    return expression.toSource();
  }

  Element? _typeElementFromExpression(Expression expression) {
    if (expression is TypeLiteral) return expression.type.element;
    if (expression is SimpleIdentifier) return expression.element;
    if (expression is PrefixedIdentifier) return expression.identifier.element;
    if (expression is PropertyAccess) return expression.propertyName.element;
    if (expression is ConstructorReference) {
      return expression.constructorName.type.element;
    }
    return null;
  }

  bool _isTypeElement(Element element) {
    return element is ClassElement ||
        element is EnumElement ||
        element is MixinElement ||
        element is TypeAliasElement ||
        element is ExtensionTypeElement;
  }

  _DocTypeReference? _parseDocTypeReference(String rawType) {
    var name = rawType.trim();
    if (name.isEmpty) return null;
    if (name.startsWith('const ')) {
      name = name.substring(6).trimLeft();
    }
    name = _stripGenerics(name);
    if (name.endsWith('?') && name.length > 1) {
      name = name.substring(0, name.length - 1);
    }
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) {
      return _DocTypeReference(null, name);
    }
    final prefix = name.substring(0, dotIndex).trim();
    final typeName = name.substring(dotIndex + 1).trim();
    if (typeName.isEmpty) return null;
    return _DocTypeReference(prefix, typeName);
  }

  String _stripGenerics(String name) {
    final index = name.indexOf('<');
    if (index == -1) return name;
    return name.substring(0, index).trimRight();
  }

  Element? _resolveTypeReference(_DocTypeReference reference) {
    final local =
        library!.getClass(reference.typeName) ??
        library!.getEnum(reference.typeName) ??
        library!.getMixin(reference.typeName) ??
        library!.getTypeAlias(reference.typeName) ??
        library!.getExtensionType(reference.typeName);
    if (local != null) return local;

    final fragment = library!.firstFragment;
    for (final import in fragment.libraryImports) {
      final prefix = import.prefix?.element;
      if (reference.prefix == null) {
        if (prefix != null) continue;
      } else {
        if (prefix == null || prefix.name != reference.prefix) continue;
      }
      final element = import.namespace.get2(reference.typeName);
      if (element != null) return element;
    }
    return null;
  }
}

class _DocTypeReference {
  final String? prefix;
  final String typeName;

  const _DocTypeReference(this.prefix, this.typeName);

  String get displayName => prefix == null ? typeName : '$prefix.$typeName';
}
