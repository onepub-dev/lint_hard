import 'dart:io';

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:lint_hard/src/document_thrown_exceptions.dart';
import 'package:lint_hard/src/document_thrown_exceptions_fix.dart';
import 'package:test/test.dart';

void main() {
  late CompilationUnit unit;
  late ResolvedUnitResult resolvedUnit;
  late ResolvedLibraryResult resolvedLibrary;
  late String fixturePath;
  late String fixtureFilePath;

  setUpAll(() async {
    fixturePath = 'test/fixtures/document_thrown_exceptions.dart';
    fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await _resolveFixture(fixtureFilePath);
    resolvedUnit = resolved.unit;
    resolvedLibrary = resolved.library;
    unit = resolvedUnit.unit;
  });

  test('detects undocumented thrown types in methods', () {
    final method = _method(unit, 'undocumentedMethod');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts documented thrown types in methods', () {
    final method = _method(unit, 'documentedMethod');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores thrown types mentioned in comments', () {
    final method = _method(unit, 'commentThrowMethod');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts multi-line throws clauses in docs', () {
    final method = _method(unit, 'documentedMultiLineThrows');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts "throws a" phrasing in docs', () {
    final method = _method(unit, 'documentedThrowsWithArticle');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts throws in the middle of a sentence', () {
    final method = _method(unit, 'documentedThrowsMidSentence');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts lists of thrown exceptions in docs', () {
    final method = _method(unit, 'documentedThrowsList');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts spaced exception names in doc lists', () {
    final method = _method(unit, 'documentedThrowsListWithSpaces');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught without rethrow', () {
    final method = _method(unit, 'throwCaughtWithoutOn');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught with on clause', () {
    final method = _method(unit, 'throwCaughtWithOn');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught with specific on clause', () {
    final method = _method(unit, 'throwCaughtWithSameOn');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('reports throws that are rethrown in catch', () {
    final method = _method(unit, 'throwCaughtWithRethrow');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('detects multiple undocumented thrown types', () {
    final method = _method(unit, 'undocumentedMultipleThrows');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException', 'MissingFileException'}));
  });

  test('dedupes repeated thrown types', () {
    final method = _method(unit, 'duplicatedThrows');
    final missing = missingThrownTypeDocs(
      method.body,
      method.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('fix inserts throws docs for rethrown exceptions', () async {
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
      contains('/// Throws [BadStateException].\n  void throwCaughtWithRethrow('),
    );
  });

  test('fix inserts throws docs for multiple exceptions', () async {
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
      contains('/// Throws [BadStateException].\n'
          '  /// Throws [MissingFileException].\n'
          '  void undocumentedMultipleThrows('),
    );
  });

  test('fix documents repeated thrown types once', () async {
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
    final match =
        RegExp(r'/// Throws \[BadStateException\]\.').allMatches(updated);
    expect(match.length, equals(1));
  });

  test('detects undocumented thrown types in constructors', () {
    final ctor = _constructor(unit, className: 'Sample');
    final missing = missingThrownTypeDocs(
      ctor.body,
      ctor.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts documented thrown types in named constructors', () {
    final ctor = _constructor(unit, className: 'Sample', name: 'named');
    final missing = missingThrownTypeDocs(
      ctor.body,
      ctor.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('detects undocumented thrown types in top-level functions', () {
    final fn = _function(unit, 'undocumentedTopLevel');
    final missing = missingThrownTypeDocs(
      fn.functionExpression.body,
      fn.documentationComment,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts documented thrown types in top-level functions', () {
    final fn = _function(unit, 'documentedTopLevel');
    final missing = missingThrownTypeDocs(
      fn.functionExpression.body,
      fn.documentationComment,
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
