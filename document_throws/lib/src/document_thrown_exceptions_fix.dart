import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'document_thrown_exceptions.dart';
import 'document_thrown_exceptions_fix_utils.dart';
import 'documentation_style.dart';
import 'throws_cache_lookup.dart';

class DocumentThrownExceptionsFix extends ResolvedCorrectionProducer {
  static const FixKind _fixKind = FixKind(
    'document_throws.fix.document_thrown_exceptions',
    DartFixKindPriority.standard,
    'Document thrown exceptions',
  );

  // Wire the fix into the analysis server context.
  DocumentThrownExceptionsFix({required super.context});

  @override
  // Apply within a single file without needing broader analysis.
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossSingleFile;

  @override
  // Expose the fix kind identifier for this lint.
  FixKind get fixKind => _fixKind;

  @override
  // Insert missing @Throwing docs for the reported executable.
  Future<void> compute(ChangeBuilder builder) async {
    if (diagnostic?.diagnosticCode != DocumentThrownExceptions.code) return;

    final target = findExecutableTarget(node);
    if (target == null) return;
    final rootPath = findProjectRoot(file);
    final documentationStyle =
        rootPath == null
            ? DocumentationStyle.docComment
            : documentationStyleForRoot(rootPath);
    final editsByPath = documentThrownExceptionEdits(
      unitResult,
      libraryResult.units,
      externalLookup: _externalLookupForPath(file),
      documentationStyle: documentationStyle,
      onlyTarget: target,
    );
    if (editsByPath.isEmpty) return;

    for (final entry in editsByPath.entries) {
      final edits = entry.value..sort((a, b) => b.offset.compareTo(a.offset));
      await builder.addDartFileEdit(entry.key, (builder) {
        for (final edit in edits) {
          if (edit.length == 0) {
            builder.addSimpleInsertion(edit.offset, edit.replacement);
          } else {
            builder.addSimpleReplacement(
              SourceRange(edit.offset, edit.length),
              edit.replacement,
            );
          }
        }
      });
    }
  }
}

ThrowsCacheLookup? _externalLookupForPath(String filePath) {
  final root = findProjectRoot(filePath);
  if (root == null) return null;
  return ThrowsCacheLookup.forProjectRoot(root);
}
