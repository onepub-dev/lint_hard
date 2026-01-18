import 'dart:io';

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:document_throws/src/document_thrown_exceptions.dart';
import 'package:document_throws/src/document_thrown_exceptions_fix.dart';
import 'package:test/test.dart';

import 'support/document_thrown_exceptions_helpers.dart';

List<SourceEdit> _collectFileEdits(
  List<SourceFileEdit> edits,
  String filePath,
) {
  final fileEdits = edits
      .where((edit) => edit.file == filePath)
      .expand((edit) => edit.edits)
      .toList();
  expect(fileEdits, isNotEmpty);
  fileEdits.sort((a, b) => a.offset.compareTo(b.offset));
  return fileEdits;
}

String _applyEdits(String content, List<SourceEdit> edits) {
  final sorted = List<SourceEdit>.from(edits)
    ..sort((a, b) => b.offset.compareTo(a.offset));
  var updated = content;
  for (final edit in sorted) {
    updated = updated.replaceRange(
      edit.offset,
      edit.offset + edit.length,
      edit.replacement,
    );
  }
  return updated;
}

void main() {
  late CompilationUnit unit;
  late ResolvedUnitResult resolvedUnit;
  late ResolvedLibraryResult resolvedLibrary;
  late String fixtureFilePath;

  setUpAll(() async {
    final fixturePath = 'test/fixtures/document_thrown_exceptions.dart';
    fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
    resolvedUnit = resolved.unit;
    resolvedLibrary = resolved.library;
    unit = resolvedUnit.unit;
  });

  Diagnostic _diagnostic(AstNode node) {
    final name = node is NamedCompilationUnitMember ? node.name : null;
    final offset = name?.offset ?? node.offset;
    final length = name?.length ?? node.length;
    return Diagnostic.forValues(
      source: resolvedUnit.libraryFragment.source,
      offset: offset,
      length: length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );
  }

  Future<String> _applyFix(AstNode node) async {
    final diagnostic = _diagnostic(node);
    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolvedLibrary,
      unitResult: resolvedUnit,
      diagnostic: diagnostic,
      selectionOffset: diagnostic.offset,
      selectionLength: diagnostic.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolvedUnit.session);
    await fix.compute(builder);

    final edits = _collectFileEdits(builder.sourceChange.edits, fixtureFilePath);
    final content = await File(fixtureFilePath).readAsString();
    return _applyEdits(content, edits);
  }

  test('fix inserts throws annotations for rethrown exceptions', () async {
    final method = findMethod(unit, 'throwCaughtWithRethrow');
    final updated = await _applyFix(method);

    expect(
      updated,
      contains('@Throws(BadStateException)\n  void throwCaughtWithRethrow('),
    );
  });

  test('fix inserts throws annotations for multiple exceptions', () async {
    final method = findMethod(unit, 'undocumentedMultipleThrows');
    final updated = await _applyFix(method);

    expect(
      updated,
      contains(
        '@Throws(BadStateException)\n'
        '  @Throws(MissingFileException)\n'
        '  void undocumentedMultipleThrows(',
      ),
    );
  });

  test('fix annotates repeated thrown types once', () async {
    final method = findMethod(unit, 'duplicatedThrows');
    final updated = await _applyFix(method);

    final match = RegExp(
      r'@Throws\(BadStateException\)\s+void duplicatedThrows',
    ).allMatches(updated);
    expect(match.length, equals(1));
  });

  test('fix adds missing @Throws annotations', () async {
    final method = findMethod(unit, 'annotatedMissingException');
    final updated = await _applyFix(method);

    expect(
      updated,
      contains(
        '@Throws(BadStateException)\n'
        '  @Throws(MissingFileException)\n'
        '  void annotatedMissingException(',
      ),
    );
  });

  test('fix adds @Throws annotations with reason', () async {
    final method = findMethod(unit, 'annotatedMissingExceptionWithSpec');
    final updated = await _applyFix(method);

    expect(
      updated,
      contains(
        "@Throws(BadStateException, reason: 'bad')\n"
        '  @Throws(MissingFileException)\n'
        '  void annotatedMissingExceptionWithSpec(',
      ),
    );
  });

  test('fix inserts throws import when missing', () async {
    final fixturePath = 'test/fixtures/document_thrown_exceptions_no_import.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
    final fn = findFunction(resolved.unit.unit, 'undocumentedTopLevel');

    final diagnostic = Diagnostic.forValues(
      source: resolved.unit.libraryFragment.source,
      offset: fn.name.offset,
      length: fn.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolved.library,
      unitResult: resolved.unit,
      diagnostic: diagnostic,
      selectionOffset: fn.name.offset,
      selectionLength: fn.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolved.unit.session);
    await fix.compute(builder);

    final fileEdits = _collectFileEdits(
      builder.sourceChange.edits,
      fixtureFilePath,
    );
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, fileEdits);
    expect(
      updated,
      contains("import 'package:document_throws/document_throws.dart';"),
    );
    expect(updated, contains('@Throws(BadStateException)'));
  });

  test('fix prefixes throws types for aliased imports', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_prefixed.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
    final fn = findFunction(resolved.unit.unit, 'undocumentedPrefixed');

    final diagnostic = Diagnostic.forValues(
      source: resolved.unit.libraryFragment.source,
      offset: fn.name.offset,
      length: fn.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolved.library,
      unitResult: resolved.unit,
      diagnostic: diagnostic,
      selectionOffset: fn.name.offset,
      selectionLength: fn.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolved.unit.session);
    await fix.compute(builder);

    final fileEdits = _collectFileEdits(
      builder.sourceChange.edits,
      fixtureFilePath,
    );
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, fileEdits);

    expect(
      updated,
      contains(
        "import 'package:document_throws/document_throws.dart';\n"
        "import 'package:yaml/yaml.dart' as y;\n",
      ),
    );
    expect(updated, contains('@Throws(y.YamlException)\n'));
  });

  test('fix keeps import and annotation formatting', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_with_imports.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
    final fn = findFunction(resolved.unit.unit, 'undocumentedTopLevel');

    final diagnostic = Diagnostic.forValues(
      source: resolved.unit.libraryFragment.source,
      offset: fn.name.offset,
      length: fn.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolved.library,
      unitResult: resolved.unit,
      diagnostic: diagnostic,
      selectionOffset: fn.name.offset,
      selectionLength: fn.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolved.unit.session);
    await fix.compute(builder);

    final fileEdits = _collectFileEdits(
      builder.sourceChange.edits,
      fixtureFilePath,
    );
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, fileEdits);

    final importBlock = RegExp(
      r"import 'dart:io';\n"
      r"\n?"
      r"import 'package:document_throws/throws\.dart';\n"
      r"import 'package:path/path\.dart';\n"
      r"\n?const sortkeyOption = 'sortkey';",
    );
    expect(updated, matches(importBlock));
    expect(
      updated,
      contains(
        '@Throws(BadStateException)\n'
        'void undocumentedTopLevel(',
      ),
    );
    expect(updated, isNot(contains('prefiximport')));
  });

  test('fix preserves shebang and constant lines', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_shebang.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
    final fn = findFunction(resolved.unit.unit, 'dsort');

    final diagnostic = Diagnostic.forValues(
      source: resolved.unit.libraryFragment.source,
      offset: fn.name.offset,
      length: fn.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolved.library,
      unitResult: resolved.unit,
      diagnostic: diagnostic,
      selectionOffset: fn.name.offset,
      selectionLength: fn.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolved.unit.session);
    await fix.compute(builder);

    final fileEdits = _collectFileEdits(
      builder.sourceChange.edits,
      fixtureFilePath,
    );
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, fileEdits);

    expect(updated, startsWith('#!/usr/bin/env dart\n'));
    expect(updated, contains("const sortkeyOption = 'sortkey';\n"));
    expect(updated, contains("const outputOption = 'output';\n"));
    expect(
      updated,
      contains("import 'package:document_throws/document_throws.dart';\n"
          "import 'package:path/path.dart';\n"),
    );
    expect(updated, contains('@Throws(ArgumentError)\nvoid dsort('));
  });

  test('fix inserts annotation after doc comment', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_doc_comment.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
    final fn = findFunction(resolved.unit.unit, 'chmod');

    final diagnostic = Diagnostic.forValues(
      source: resolved.unit.libraryFragment.source,
      offset: fn.name.offset,
      length: fn.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolved.library,
      unitResult: resolved.unit,
      diagnostic: diagnostic,
      selectionOffset: fn.name.offset,
      selectionLength: fn.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolved.unit.session);
    await fix.compute(builder);

    final edits = builder.sourceChange.edits;
    expect(edits, isNotEmpty);
    final fileEdit = edits.firstWhere((edit) => edit.file == fixtureFilePath);
    final updated =
        SourceEdit.applySequence(resolved.unit.content, fileEdit.edits);

    expect(
      updated,
      contains(
        '/// Sets the permissions on a file.\n'
        '@Throws(ChModException)\n'
        'void chmod(',
      ),
    );
  });
}
