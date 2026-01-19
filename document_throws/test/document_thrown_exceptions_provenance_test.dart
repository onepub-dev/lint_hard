import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:document_throws/src/document_thrown_exceptions_fix_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/document_thrown_exceptions_helpers.dart';

void main() {
  test('fix --origin adds provenance for external throws', () async {
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

    expect(updated, contains('/// @Throwing(\n'));
    expect(updated, contains('///   FormatException,\n'));
    expect(updated, contains("///   call: 'dart:core|RegExp.new',\n"));
    expect(updated, contains("///   origin: 'dart:core|RegExp',\n"));
    expect(updated, contains('/// )\n'));
  });

  test('fix --origin preserves reason without provenance', () async {
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
    final reasonPattern =
        "/// @Throwing\\(BadStateException, reason: 'bad'\\)";
    expect(RegExp(reasonPattern).allMatches(updated).length, 1);
  });

  test('fix --origin shortens file origin to package name', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_provenance.dart';
    final resolved = await resolveFixture(File(fixturePath).absolute.path);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      externalLookup: FilePathProvenanceLookup(),
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

    expect(updated, contains("origin: 'posix|_buildPasswd'"));
  });

  test('fix --origin wraps long throws annotation lines', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_provenance.dart';
    final resolved = await resolveFixture(File(fixturePath).absolute.path);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      externalLookup: LongProvenanceLookup(),
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

    expect(updated, contains('/// @Throwing(\n'));
    expect(updated, contains('///   FormatException,\n'));
    expect(updated, contains("///   call: 'dart:core|RegExp.new',\n"));
    expect(
      updated,
      contains(
        "///   origin: 'very_long_package_name|veryLongOriginMethodName',\n",
      ),
    );
    expect(updated, contains('/// )\n'));
  });

  test('fix without --origin strips provenance from annotations', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_provenance_existing.dart';
    final resolved = await resolveFixture(File(fixturePath).absolute.path);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      externalLookup: ProvenanceThrowsCacheLookup(),
      includeSource: false,
    );
    expect(editsByFile, isNotEmpty);
    final edits = editsByFile[resolved.unit.path] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);
    edits.sort((a, b) => b.offset.compareTo(a.offset));

    final updated = SourceEdit.applySequence(
      resolved.unit.content,
      edits,
    );

    expect(updated, contains('/// @Throwing(FormatException)\n'));
    expect(updated, isNot(contains('call:')));
    expect(updated, isNot(contains('origin:')));
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
    expect(partUpdated, contains('/// @Throwing(BadStateException)'));
    expect(
      partUpdated,
      isNot(contains('package:document_throws_annotation/document_throws_annotation.dart')),
    );

    final libraryEdits = editsByFile[File(libraryPath).absolute.path];
    expect(libraryEdits, isNull);
    await collection.dispose();
  });

  test('fix output with provenance compiles with doc comments', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_provenance.dart';
    final resolved = await resolveFixture(File(fixturePath).absolute.path);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      externalLookup: ProvenanceThrowsCacheLookup(),
      includeSource: true,
    );
    final edits = editsByFile[resolved.unit.path] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);
    edits.sort((a, b) => b.offset.compareTo(a.offset));

    final updated = SourceEdit.applySequence(
      resolved.unit.content,
      edits,
    );

    final tempRoot = Directory(p.join(Directory.current.path, '.dart_tool'));
    final tempDir = await tempRoot.createTemp(
      'document_throws_fix_compile_',
    );
    try {
      final file = File('${tempDir.path}/sample.dart');
      await file.writeAsString(updated);

      final collection = AnalysisContextCollection(
        includedPaths: [file.path],
        resourceProvider: PhysicalResourceProvider.INSTANCE,
      );
      final context = collection.contextFor(file.path);
      final session = context.currentSession;
      final unitResult = await session.getResolvedUnit(file.path);
      if (unitResult is! ResolvedUnitResult) {
        throw StateError('Failed to resolve temp file');
      }
      final errors = unitResult.diagnostics
          .where(
            (diagnostic) =>
                diagnostic.diagnosticCode.severity == DiagnosticSeverity.ERROR,
          )
          .toList();
      expect(errors, isEmpty);
      await collection.dispose();
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
