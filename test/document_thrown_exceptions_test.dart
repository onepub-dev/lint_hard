import 'dart:io';

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:lint_hard/src/document_thrown_exceptions.dart';
import 'package:lint_hard/src/document_thrown_exceptions_fix.dart';
import 'package:lint_hard/src/throws_cache.dart';
import 'package:lint_hard/src/throws_cache_lookup.dart';
import 'package:test/test.dart';

void main() {
  late CompilationUnit unit;
  late ResolvedUnitResult resolvedUnit;
  late ResolvedLibraryResult resolvedLibrary;
  late String fixturePath;
  late String fixtureFilePath;
  late Map<String, CompilationUnit> unitsByPath;

  setUpAll(() async {
    fixturePath = 'test/fixtures/document_thrown_exceptions.dart';
    fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await _resolveFixture(fixtureFilePath);
    resolvedUnit = resolved.unit;
    resolvedLibrary = resolved.library;
    unitsByPath = {
      for (final unit in resolvedLibrary.units) unit.path: unit.unit,
    };
    unit = resolvedUnit.unit;
  });

  Set<String> _missing(
    FunctionBody body,
    NodeList<Annotation>? metadata, {
    bool allowSourceFallback = false,
    ThrowsCacheLookup? externalLookup,
  }) {
    return missingThrownTypeDocs(
      body,
      metadata,
      allowSourceFallback: allowSourceFallback,
      unitsByPath: unitsByPath,
      externalLookup: externalLookup,
    );
  }

  test('detects undocumented thrown types in methods', () {
    final method = _method(unit, 'undocumentedMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts annotated thrown types in methods', () {
    final method = _method(unit, 'documentedMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores thrown types mentioned in comments', () {
    final method = _method(unit, 'commentThrowMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts annotation with multiple thrown types', () {
    final method = _method(unit, 'documentedThrowsList');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts annotation with reason', () {
    final method = _method(unit, 'documentedThrowsWithReason');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught without rethrow', () {
    final method = _method(unit, 'throwCaughtWithoutOn');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught with on clause', () {
    final method = _method(unit, 'throwCaughtWithOn');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught with specific on clause', () {
    final method = _method(unit, 'throwCaughtWithSameOn');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('reports throws that are rethrown in catch', () {
    final method = _method(unit, 'throwCaughtWithRethrow');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('detects multiple undocumented thrown types', () {
    final method = _method(unit, 'undocumentedMultipleThrows');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException', 'MissingFileException'}));
  });

  test('dedupes repeated thrown types', () {
    final method = _method(unit, 'duplicatedThrows');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('propagates throws from called methods', () {
    final method = _method(unit, 'callerUsesThrowingMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('propagates throws from sdk cache', () {
    final method = _method(unit, 'usesRegExp');
    final missing = _missing(
      method.body,
      method.metadata,
      externalLookup: _TestThrowsCacheLookup(),
    );

    expect(missing, equals({'FormatException'}));
  });

  // TODO: doc-based propagation disabled; re-enable if docs are used again.
  // test('propagates throws from called method docs', () {
  //   final method = _method(unit, 'callerUsesDocThrows');
  //   final missing = _missing(
  //     method.body,
  //     method.documentationComment,
  //     allowSourceFallback: true,
  //   );
  //
  //   expect(missing, equals({'BadStateException'}));
  // });

  test('ignores throws handled after a call', () {
    final method = _method(unit, 'callerCatchesThrowingMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('fix inserts throws annotations for rethrown exceptions', () async {
    final method = _method(resolvedUnit.unit, 'throwCaughtWithRethrow');

    final diagnostic = Diagnostic.forValues(
      source: resolvedUnit.libraryFragment.source,
      offset: method.name.offset,
      length: method.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolvedLibrary,
      unitResult: resolvedUnit,
      diagnostic: diagnostic,
      selectionOffset: method.name.offset,
      selectionLength: method.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolvedUnit.session);
    await fix.compute(builder);

    final edits = builder.sourceChange.edits;
    expect(edits, isNotEmpty);
    final fileEdit = edits.firstWhere((edit) => edit.file == fixtureFilePath);
    final updated =
        SourceEdit.applySequence(resolvedUnit.content, fileEdit.edits);
    expect(
      updated,
      contains('@Throws([BadStateException])\n  void throwCaughtWithRethrow('),
    );
  });

  test('fix inserts throws annotations for multiple exceptions', () async {
    final method = _method(resolvedUnit.unit, 'undocumentedMultipleThrows');

    final diagnostic = Diagnostic.forValues(
      source: resolvedUnit.libraryFragment.source,
      offset: method.name.offset,
      length: method.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolvedLibrary,
      unitResult: resolvedUnit,
      diagnostic: diagnostic,
      selectionOffset: method.name.offset,
      selectionLength: method.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolvedUnit.session);
    await fix.compute(builder);

    final edits = builder.sourceChange.edits;
    expect(edits, isNotEmpty);
    final fileEdit = edits.firstWhere((edit) => edit.file == fixtureFilePath);
    final updated =
        SourceEdit.applySequence(resolvedUnit.content, fileEdit.edits);
    expect(
      updated,
      contains(
        '@Throws([BadStateException, MissingFileException])\n'
        '  void undocumentedMultipleThrows(',
      ),
    );
  });

  test('fix annotates repeated thrown types once', () async {
    final method = _method(resolvedUnit.unit, 'duplicatedThrows');

    final diagnostic = Diagnostic.forValues(
      source: resolvedUnit.libraryFragment.source,
      offset: method.name.offset,
      length: method.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolvedLibrary,
      unitResult: resolvedUnit,
      diagnostic: diagnostic,
      selectionOffset: method.name.offset,
      selectionLength: method.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolvedUnit.session);
    await fix.compute(builder);

    final edits = builder.sourceChange.edits;
    expect(edits, isNotEmpty);
    final fileEdit = edits.firstWhere((edit) => edit.file == fixtureFilePath);
    final updated =
        SourceEdit.applySequence(resolvedUnit.content, fileEdit.edits);
    final match = RegExp(
      r'@Throws\(\[BadStateException\]\)\s+void duplicatedThrows',
    ).allMatches(updated);
    expect(match.length, equals(1));
  });

  test('fix updates existing @Throws list', () async {
    final method = _method(resolvedUnit.unit, 'annotatedMissingException');

    final diagnostic = Diagnostic.forValues(
      source: resolvedUnit.libraryFragment.source,
      offset: method.name.offset,
      length: method.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolvedLibrary,
      unitResult: resolvedUnit,
      diagnostic: diagnostic,
      selectionOffset: method.name.offset,
      selectionLength: method.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolvedUnit.session);
    await fix.compute(builder);

    final edits = builder.sourceChange.edits;
    expect(edits, isNotEmpty);
    final fileEdit = edits.firstWhere((edit) => edit.file == fixtureFilePath);
    final updated =
        SourceEdit.applySequence(resolvedUnit.content, fileEdit.edits);
    expect(
      updated,
      contains(
        '@Throws([BadStateException, MissingFileException])\n'
        '  void annotatedMissingException(',
      ),
    );
  });

  test('fix updates @Throws list with ThrowSpec', () async {
    final method =
        _method(resolvedUnit.unit, 'annotatedMissingExceptionWithSpec');

    final diagnostic = Diagnostic.forValues(
      source: resolvedUnit.libraryFragment.source,
      offset: method.name.offset,
      length: method.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: resolvedLibrary,
      unitResult: resolvedUnit,
      diagnostic: diagnostic,
      selectionOffset: method.name.offset,
      selectionLength: method.name.length,
    );
    final fix = DocumentThrownExceptionsFix(context: producerContext);
    final builder = ChangeBuilder(session: resolvedUnit.session);
    await fix.compute(builder);

    final edits = builder.sourceChange.edits;
    expect(edits, isNotEmpty);
    final fileEdit = edits.firstWhere((edit) => edit.file == fixtureFilePath);
    final updated =
        SourceEdit.applySequence(resolvedUnit.content, fileEdit.edits);
    expect(
      updated,
      contains(
        "@Throws([ThrowSpec(BadStateException, 'bad'), MissingFileException])\n"
        '  void annotatedMissingExceptionWithSpec(',
      ),
    );
  });

  test('fix inserts throws import when missing', () async {
    final fixturePath = 'test/fixtures/document_thrown_exceptions_no_import.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await _resolveFixture(fixtureFilePath);
    final unit = resolved.unit.unit;
    final library = resolved.library;
    final fn = _function(unit, 'undocumentedTopLevel');

    final diagnostic = Diagnostic.forValues(
      source: resolved.unit.libraryFragment.source,
      offset: fn.name.offset,
      length: fn.name.length,
      diagnosticCode: DocumentThrownExceptions.code,
      message: DocumentThrownExceptions.code.problemMessage,
      correctionMessage: DocumentThrownExceptions.code.correctionMessage,
    );

    final producerContext = CorrectionProducerContext.createResolved(
      libraryResult: library,
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
    final fileEdit =
        edits.firstWhere((edit) => edit.file == fixtureFilePath);
    final updated =
        SourceEdit.applySequence(resolved.unit.content, fileEdit.edits);
    expect(updated, contains("import 'package:lint_hard/throws.dart';"));
    expect(updated, contains('@Throws([BadStateException])'));
  });

  test('detects undocumented thrown types in constructors', () {
    final ctor = _constructor(unit, className: 'Sample');
    final missing = _missing(
      ctor.body,
      ctor.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts annotated thrown types in named constructors', () {
    final ctor = _constructor(unit, className: 'Sample', name: 'named');
    final missing = _missing(
      ctor.body,
      ctor.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('detects undocumented thrown types in top-level functions', () {
    final fn = _function(unit, 'undocumentedTopLevel');
    final missing = _missing(
      fn.functionExpression.body,
      fn.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts annotated thrown types in top-level functions', () {
    final fn = _function(unit, 'documentedTopLevel');
    final missing = _missing(
      fn.functionExpression.body,
      fn.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });
}

MethodDeclaration _method(CompilationUnit unit, String name) {
  final finder = _MethodFinder(name);
  unit.accept(finder);
  final method = finder.found;
  if (method == null) {
    throw StateError('Method not found: $name');
  }
  return method;
}

ConstructorDeclaration _constructor(
  CompilationUnit unit, {
  required String className,
  String? name,
}) {
  final finder = _ConstructorFinder(className, name);
  unit.accept(finder);
  final ctor = finder.found;
  if (ctor == null) {
    throw StateError('Constructor not found: $className${name ?? ''}');
  }
  return ctor;
}

FunctionDeclaration _function(CompilationUnit unit, String name) {
  final finder = _FunctionFinder(name);
  unit.accept(finder);
  final fn = finder.found;
  if (fn == null) {
    throw StateError('Function not found: $name');
  }
  return fn;
}

class _MethodFinder extends RecursiveAstVisitor<void> {
  final String name;
  MethodDeclaration? found;

  _MethodFinder(this.name);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) {
      found = node;
      return;
    }
    super.visitMethodDeclaration(node);
  }
}

class _ConstructorFinder extends RecursiveAstVisitor<void> {
  final String className;
  final String? name;
  ConstructorDeclaration? found;

  _ConstructorFinder(this.className, this.name);

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final matchesClass = node.returnType.name == className;
    final constructorName = node.name?.lexeme;
    final matchesName = constructorName == name;
    if (matchesClass && matchesName) {
      found = node;
      return;
    }
    super.visitConstructorDeclaration(node);
  }
}

class _FunctionFinder extends RecursiveAstVisitor<void> {
  final String name;
  FunctionDeclaration? found;

  _FunctionFinder(this.name);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.name.lexeme == name && node.parent is CompilationUnit) {
      found = node;
      return;
    }
    super.visitFunctionDeclaration(node);
  }
}

class _ResolvedFixture {
  final ResolvedUnitResult unit;
  final ResolvedLibraryResult library;

  const _ResolvedFixture(this.unit, this.library);
}

Future<_ResolvedFixture> _resolveFixture(String filePath) async {
  final collection = AnalysisContextCollection(
    includedPaths: [filePath],
    resourceProvider: PhysicalResourceProvider.INSTANCE,
  );
  final context = collection.contextFor(filePath);
  final session = context.currentSession;
  final unitResult = await session.getResolvedUnit(filePath);
  final libraryResult = await session.getResolvedLibrary(filePath);
  if (unitResult is! ResolvedUnitResult ||
      libraryResult is! ResolvedLibraryResult) {
    throw StateError('Failed to resolve fixture: $filePath');
  }
  return _ResolvedFixture(unitResult, libraryResult);
}

class _TestThrowsCacheLookup extends ThrowsCacheLookup {
  _TestThrowsCacheLookup()
    : super(
        cache: ThrowsCache(Directory.systemTemp.path),
        packageVersions: const {},
        packageSources: const {},
        sdkVersion: 'test',
        sdkRoot: null,
      );

  @override
  List<String> lookup(ExecutableElement element) {
    final uri = element.library.firstFragment.source.uri.toString();
    if (uri == 'dart:core' &&
        element is ConstructorElement &&
        element.enclosingElement.name == 'RegExp') {
      return const ['FormatException'];
    }
    return const <String>[];
  }
}
