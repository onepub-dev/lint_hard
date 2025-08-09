import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'sort_fields_then_constructors.dart';

PluginBase createPlugin() => _LintHardPlugin();

class _LintHardPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs _) => [
    FieldsFirstConstructorsNext(),
  ];
}
