import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:document_throws/src/document_thrown_exceptions_fix_utils.dart';
import 'package:test/test.dart';

import 'support/document_thrown_exceptions_helpers.dart';

void main() {
  test('fix --source adds provenance for external throws', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_provenance.dart';
    final resolved = await resolveFixture(File(fixturePath).absolute.path);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      externalLookup: ProvenanceThrowsCacheLookup(),
      includeSource: true,
    );
    expect(editsByFile, isNotEmpty);
    final edits = editsByFile[resolved.unit.path] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);
    edits.sort((a, b) => b.offset.compareTo(a.offset));

    final updated = SourceEdit.applySequence(
      resolved.unit.content,
      edits,
    );

    final callPattern =
        r"@Throws\(FormatException, call: 'dart:core\|RegExp#RegExp(?:\.new)?\(String,bool,bool,bool,bool\):\d+'";
    expect(updated, matches(RegExp(callPattern)));
    expect(updated, contains("origin: 'dart:core|RegExp#RegExp():999'"));
  });

  test('fix --source preserves reason without provenance', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_reason_source.dart';
    final resolved = await resolveFixture(File(fixturePath).absolute.path);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      includeSource: true,
    );
    expect(editsByFile, isNotEmpty);
    final edits = editsByFile[resolved.unit.path] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);
    edits.sort((a, b) => b.offset.compareTo(a.offset));

    final updated = SourceEdit.applySequence(
      resolved.unit.content,
      edits,
    );
    final reasonPattern = "@Throws\\(BadStateException, reason: 'bad'\\)";
    expect(RegExp(reasonPattern).allMatches(updated).length, 1);
  });

  test('fix inserts throws import into library for part files', () async {
    final partPath =
        'test/fixtures/document_thrown_exceptions_part_library_part.dart';
    final libraryPath =
        'test/fixtures/document_thrown_exceptions_part_library.dart';
    final partFilePath = File(partPath).absolute.path;
    final collection = AnalysisContextCollection(
      includedPaths: [partFilePath],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );
    final context = collection.contextFor(partFilePath);
    final session = context.currentSession;
    final unitResult = await session.getResolvedUnit(partFilePath);
    final libraryResult = await session.getResolvedLibraryContaining(
      partFilePath,
    );
    if (unitResult is! ResolvedUnitResult ||
        libraryResult is! ResolvedLibraryResult) {
      throw StateError('Failed to resolve fixture: $partFilePath');
    }

    final editsByFile = documentThrownExceptionEdits(
      unitResult,
      libraryResult.units,
    );
    expect(editsByFile, isNotEmpty);

    final partEdits = editsByFile[unitResult.path];
    expect(partEdits, isNotNull);
    partEdits!.sort((a, b) => b.offset.compareTo(a.offset));
    final partUpdated = SourceEdit.applySequence(
      unitResult.content,
      partEdits,
    );
    expect(partUpdated, contains('@Throws(BadStateException)'));
    expect(partUpdated, isNot(contains('package:document_throws/throws.dart')));

    final libraryEdits = editsByFile[File(libraryPath).absolute.path];
    expect(libraryEdits, isNotNull);
    libraryEdits!.sort((a, b) => b.offset.compareTo(a.offset));
    final libraryContent = File(libraryPath).readAsStringSync();
    final libraryUpdated = SourceEdit.applySequence(
      libraryContent,
      libraryEdits,
    );
    expect(
      libraryUpdated,
      contains("import 'package:document_throws/throws.dart';"),
    );
    await collection.dispose();
  });
}
