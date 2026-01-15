import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/document_thrown_exceptions.dart';
import 'src/document_thrown_exceptions_fix.dart';
import 'src/reorder_members_fix.dart';
import 'src/sort_fields_then_constructors.dart';

final plugin = LintHardPlugin();

class LintHardPlugin extends Plugin {
  @override
  String get name => 'lint_hard';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(DocumentThrownExceptions());
    registry.registerFixForRule(
      DocumentThrownExceptions.code,
      DocumentThrownExceptionsFix.new,
    );
    registry.registerLintRule(FieldsFirstConstructorsNext());
    registry.registerFixForRule(
      FieldsFirstConstructorsNext.code,
      ReorderMembersFix.new,
    );
  }
}
