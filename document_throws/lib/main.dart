import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/document_thrown_exceptions.dart';
import 'src/document_thrown_exceptions_fix.dart';
import 'src/throws_index_up_to_date.dart';

final plugin = DocumentThrowsPlugin();

class DocumentThrowsPlugin extends Plugin {
  @override
  String get name => 'document_throws';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(DocumentThrownExceptions());
    registry.registerFixForRule(
      DocumentThrownExceptions.code,
      DocumentThrownExceptionsFix.new,
    );
    registry.registerWarningRule(ThrowsIndexUpToDate());
  }
}
