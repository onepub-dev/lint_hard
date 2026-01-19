import 'dart:io';

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:document_throws/src/document_thrown_exceptions.dart';
import 'package:document_throws/src/document_thrown_exceptions_fix.dart';
import 'package:document_throws/src/document_thrown_exceptions_fix_utils.dart';
import 'package:document_throws/src/documentation_style.dart';
import 'package:test/test.dart';

import 'support/document_thrown_exceptions_helpers.dart';

List<SourceEdit> _collectFileEdits(
  List<SourceFileEdit> edits,
  String filePath,
) {
  final fileEdits =
      edits
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

    final edits = _collectFileEdits(
      builder.sourceChange.edits,
      fixtureFilePath,
    );
    final content = await File(fixtureFilePath).readAsString();
    return _applyEdits(content, edits);
  }

  test('fix inserts @Throwing doc comments for rethrown exceptions', () async {
    final method = findMethod(unit, 'throwCaughtWithRethrow');
    final updated = await _applyFix(method);

    expect(
      updated,
      contains(
        '/// @Throwing(BadStateException)\n  void throwCaughtWithRethrow(',
      ),
    );
  });

  test('fix inserts @Throwing doc comments for multiple exceptions', () async {
    final method = findMethod(unit, 'undocumentedMultipleThrows');
    final updated = await _applyFix(method);

    expect(
      updated,
      contains(
        '/// @Throwing(BadStateException)\n'
        '  /// @Throwing(MissingFileException)\n'
        '  void undocumentedMultipleThrows(',
      ),
    );
  });

  test('fix annotates repeated thrown types once', () async {
    final method = findMethod(unit, 'duplicatedThrows');
    final updated = await _applyFix(method);

    final match = RegExp(
      r'/// @Throwing\(BadStateException\)\s+void duplicatedThrows',
    ).allMatches(updated);
    expect(match.length, equals(1));
  });

  test('fix adds missing @Throwing doc comments', () async {
    final method = findMethod(unit, 'annotatedMissingException');
    final updated = await _applyFix(method);

    expect(
      updated,
      contains(
        '/// @Throwing(BadStateException)\n'
        '  /// @Throwing(MissingFileException)\n'
        '  void annotatedMissingException(',
      ),
    );
  });

  test('fix adds @Throwing doc comments with reason', () async {
    final method = findMethod(unit, 'annotatedMissingExceptionWithSpec');
    final updated = await _applyFix(method);

    expect(
      updated,
      contains(
        "/// @Throwing(BadStateException, reason: 'bad')\n"
        '  /// @Throwing(MissingFileException)\n'
        '  void annotatedMissingExceptionWithSpec(',
      ),
    );
  });

  test('fix uses doc comments without adding import by default', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_no_import.dart';
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
      isNot(
        contains(
          "import 'package:document_throws_annotation/document_throws_annotation.dart';",
        ),
      ),
    );
    expect(updated, contains('/// @Throwing(BadStateException)'));
  });

  test('fix inserts annotation import in annotation mode', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_no_import.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      documentationStyle: DocumentationStyle.annotation,
    );
    expect(editsByFile, isNotEmpty);

    final fileEdits = editsByFile[fixtureFilePath];
    expect(fileEdits, isNotNull);
    fileEdits!.sort((a, b) => b.offset.compareTo(a.offset));
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, fileEdits);
    expect(
      updated,
      contains(
        "import 'package:document_throws_annotation/document_throws_annotation.dart';",
      ),
    );
    expect(updated, contains('@Throwing(BadStateException)'));
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
      isNot(
        contains(
          "import 'package:document_throws_annotation/document_throws_annotation.dart';",
        ),
      ),
    );
    expect(updated, contains('/// @Throwing(y.YamlException)\n'));
  });

  test('fix prefixes external throws types for aliased imports', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_prefixed_external.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      externalLookup: PrefixedThrowsCacheLookup(),
    );
    final edits = editsByFile[resolved.unit.path] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);

    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, edits);
    expect(updated, contains('/// @Throwing(y.YamlException)\n'));
  });

  test('fix keeps import ordering in annotation mode', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_with_imports.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      documentationStyle: DocumentationStyle.annotation,
    );
    final fileEdits = editsByFile[fixtureFilePath];
    expect(fileEdits, isNotNull);
    fileEdits!.sort((a, b) => b.offset.compareTo(a.offset));
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, fileEdits);

    final importBlock = RegExp(
      r"import 'dart:io';\n"
      r"\n?"
      r"import 'package:document_throws_annotation/document_throws_annotation\.dart';\n"
      r"import 'package:path/path\.dart';\n"
      r"\n*const sortkeyOption = 'sortkey';",
    );
    expect(updated, matches(importBlock));
    expect(
      updated,
      contains(
        '@Throwing(BadStateException)\n'
        'void undocumentedTopLevel(',
      ),
    );
    expect(updated, isNot(contains('prefiximport')));
  });

  test('fix preserves shebang and constant lines', () async {
    final fixturePath = 'test/fixtures/document_thrown_exceptions_shebang.dart';
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
      isNot(
        contains(
          "import 'package:document_throws_annotation/document_throws_annotation.dart';",
        ),
      ),
    );
    expect(updated, contains('/// @Throwing(ArgumentError)\nvoid dsort('));
  });

  test('fix skips adding @Throwing when doc comment mentions exception', () async {
    final fixturePath = 'test/fixtures/document_thrown_exceptions.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      documentationStyle: DocumentationStyle.docComment,
    );
    final edits = editsByFile[fixtureFilePath] ?? const <SourceEdit>[];
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, edits);

    final signatureIndex = updated.indexOf('void mentionedThrowWithoutTag');
    expect(signatureIndex, greaterThan(0));
    final commentIndex = updated.lastIndexOf(
      '/// Throws [BadStateException].',
      signatureIndex,
    );
    expect(commentIndex, greaterThan(0));
    final block = updated.substring(commentIndex, signatureIndex);
    expect(block, isNot(contains('@Throwing(BadStateException)')));
  });

  test('fix adds @Throwing when forced even if doc mentions exception', () async {
    final fixturePath = 'test/fixtures/document_thrown_exceptions.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      documentationStyle: DocumentationStyle.docComment,
      honorDocMentions: false,
    );
    final edits = editsByFile[fixtureFilePath] ?? const <SourceEdit>[];
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, edits);

    final signatureIndex = updated.indexOf('void mentionedThrowWithoutTag');
    expect(signatureIndex, greaterThan(0));
    final commentIndex = updated.lastIndexOf(
      '/// Throws [BadStateException].',
      signatureIndex,
    );
    expect(commentIndex, greaterThan(0));
    final block = updated.substring(commentIndex, signatureIndex);
    expect(block, contains('@Throwing(BadStateException)'));
  });

  test('fix respects doc mentions in annotation mode', () async {
    final fixturePath = 'test/fixtures/document_thrown_exceptions.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      documentationStyle: DocumentationStyle.annotation,
    );
    final edits = editsByFile[fixtureFilePath] ?? const <SourceEdit>[];
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, edits);

    final signatureIndex = updated.indexOf('void mentionedThrowWithoutTag');
    expect(signatureIndex, greaterThan(0));
    final commentIndex = updated.lastIndexOf(
      '/// Throws [BadStateException].',
      signatureIndex,
    );
    expect(commentIndex, greaterThan(0));
    final block = updated.substring(commentIndex, signatureIndex);
    expect(block, isNot(contains('@Throwing(BadStateException)')));
  });

  test('fix appends @Throwing tags to doc comments', () async {
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
    final updated = SourceEdit.applySequence(
      resolved.unit.content,
      fileEdit.edits,
    );

    expect(
      updated,
      contains(
        '/// Sets the permissions on a file.\n'
        '/// @Throwing(ChModException)\n'
        'void chmod(',
      ),
    );
  });

  test('fix removes annotations when using doc comments', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_switch_style.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      documentationStyle: DocumentationStyle.docComment,
    );
    final edits = editsByFile[fixtureFilePath] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, edits);

    expect(updated, isNot(contains('\n@Throwing(BadStateException)')));
    expect(updated, contains('/// @Throwing(BadStateException)'));
    expect(updated, contains('/// @Throwing(MissingFileException)'));
  });

  test('fix removes doc comment tags when using annotations', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_switch_style.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      documentationStyle: DocumentationStyle.annotation,
      honorDocMentions: false,
    );
    final edits = editsByFile[fixtureFilePath] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, edits);

    expect(updated, isNot(contains('/// @Throwing(')));
    expect(updated, contains('@Throwing(BadStateException)'));
    expect(updated, contains('@Throwing(MissingFileException)'));
  });

  test('fix removes orphaned provenance lines without --origin', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_remove_origin.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      includeSource: false,
      documentationStyle: DocumentationStyle.docComment,
    );
    final edits = editsByFile[fixtureFilePath] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, edits);

    expect(updated, isNot(contains('call:')));
    expect(updated, isNot(contains('origin:')));
    expect(updated, isNot(contains('/// ArgumentError,')));
    expect(
      updated,
      contains(RegExp(r'/// @Throwing\(ArgumentError\)\nvoid main')),
    );
  });

  test('fix removes provenance without leaving hanging type lines', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_remove_origin_reason.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);

    final editsByFile = documentThrownExceptionEdits(
      resolved.unit,
      resolved.library.units,
      includeSource: false,
      documentationStyle: DocumentationStyle.docComment,
    );
    final edits = editsByFile[fixtureFilePath] ?? const <SourceEdit>[];
    expect(edits, isNotEmpty);
    final content = await File(fixtureFilePath).readAsString();
    final updated = _applyEdits(content, edits);

    expect(updated, isNot(contains('call:')));
    expect(updated, isNot(contains('origin:')));
    expect(updated, isNot(contains('/// ArgumentError,')));
    expect(
      updated,
      contains(
        "/// @Throwing(ArgumentError, reason: 'Because bad things')\nvoid main",
      ),
    );
  });
}
