import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/reorder_members_fix.dart';
import 'src/sort_fields_then_constructors.dart';

final plugin = LintHardPlugin();

class LintHardPlugin extends Plugin {
  @override
  String get name => 'lint_hard';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(FieldsFirstConstructorsNext());
    registry.registerFixForRule(
      FieldsFirstConstructorsNext.code,
      ReorderMembersFix.new,
    );
  }
}
