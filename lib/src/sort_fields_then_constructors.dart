import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

class FieldsFirstConstructorsNext extends AnalysisRule {
  static const LintCode code = LintCode(
    'fields_first_constructors_next',
    'Order members as: fields first, then constructors, then others.',
    correctionMessage:
        'Move fields to the top, constructors next, then methods/getters/etc.',
  );

  FieldsFirstConstructorsNext()
      : super(
          name: code.name,
          description:
              'Ensure fields come first, constructors next, then other members.',
        );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry
      ..addClassDeclaration(this, visitor)
      ..addMixinDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (_needsReorder(node.members)) {
      rule.reportAtToken(node.name);
    }
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    if (_needsReorder(node.members)) {
      rule.reportAtToken(node.name);
    }
  }

  bool _needsReorder(List<ClassMember> members) {
    if (members.isEmpty) return false;

    final fieldIdxs = <int>[];
    final ctorIdxs = <int>[];

    for (var i = 0; i < members.length; i++) {
      final m = members[i];
      if (m is FieldDeclaration) fieldIdxs.add(i);
      if (m is ConstructorDeclaration) ctorIdxs.add(i);
    }

    if (ctorIdxs.isEmpty) return false;

    final firstCtor = ctorIdxs.reduce((a, b) => a < b ? a : b);
    final lastField =
        fieldIdxs.isNotEmpty ? fieldIdxs.reduce((a, b) => a > b ? a : b) : -1;

    // Any ctor before the last field?
    if (lastField >= 0 && ctorIdxs.any((c) => c < lastField)) return true;

    // If constructors exist, the first non-field must be a constructor.
    final firstNonField = members.indexWhere((m) => m is! FieldDeclaration);
    if (firstNonField >= 0 &&
        members[firstNonField] is! ConstructorDeclaration) {
      return true;
    }

    // No fields after the first constructor.
    if (fieldIdxs.any((f) => f > firstCtor)) return true;

    return false;
  }
}
