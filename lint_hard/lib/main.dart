import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:document_throws/src/document_thrown_exceptions.dart';
import 'package:document_throws/src/document_thrown_exceptions_fix.dart';
import 'package:document_throws/src/throws_index_up_to_date.dart';

import 'src/reorder_members_fix.dart';
import 'src/sort_fields_then_constructors.dart';

final plugin = LintHardPlugin();

class LintHardPlugin extends Plugin {
  @override
  // Plugin name used by the analysis server.
  String get name => 'lint_hard';

  @override
  // Register lint rules and their associated fixes.
  void register(PluginRegistry registry) {
    registry.registerWarningRule(DocumentThrownExceptions());
    registry.registerFixForRule(
      DocumentThrownExceptions.code,
      DocumentThrownExceptionsFix.new,
    );
    registry.registerWarningRule(ThrowsIndexUpToDate());
    registry.registerWarningRule(FieldsFirstConstructorsNext());
    registry.registerFixForRule(
      FieldsFirstConstructorsNext.code,
      ReorderMembersFix.new,
    );
  }
}
