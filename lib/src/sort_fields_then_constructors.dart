// sort_fields_then_constructors.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'reorder_members_fix.dart';

class FieldsFirstConstructorsNext extends DartLintRule {
  const FieldsFirstConstructorsNext() : super(code: _code);

  static const _code = LintCode(
    name: 'fields_first_constructors_next',
    problemMessage:
        'Order members as: fields first, then constructors, then others.',
    correctionMessage:
        'Move fields to the top, constructors next, then methods/getters/etc.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    bool needsReorder(List<ClassMember> members) {
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

    context.registry
      ..addClassDeclaration((node) {
        if (needsReorder(node.members)) {
          reporter.atToken(node.name, _code); // ✅ Token ok
        }
      })
      ..addMixinDeclaration((node) {
        if (needsReorder(node.members)) {
          reporter.atToken(node.name, _code); // ✅
        }
      });

    // Enums skipped for now.
  }

  @override
  List<Fix> getFixes() => [ReorderMembersFix()];
}
