import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:lint_hard/src/document_thrown_exceptions.dart';
import 'package:lint_hard/src/throws_cache_lookup.dart';
import 'package:test/test.dart';

import 'support/document_thrown_exceptions_helpers.dart';

void main() {
  late CompilationUnit unit;
  late ResolvedUnitResult resolvedUnit;
  late ResolvedLibraryResult resolvedLibrary;
  late Map<String, CompilationUnit> unitsByPath;

  setUpAll(() async {
    final fixturePath = 'test/fixtures/document_thrown_exceptions.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
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
    final method = findMethod(unit, 'undocumentedMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts annotated thrown types in methods', () {
    final method = findMethod(unit, 'documentedMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores thrown types mentioned in comments', () {
    final method = findMethod(unit, 'commentThrowMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts annotation with multiple thrown types', () {
    final method = findMethod(unit, 'documentedThrowsList');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('accepts annotation with reason', () {
    final method = findMethod(unit, 'documentedThrowsWithReason');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught without rethrow', () {
    final method = findMethod(unit, 'throwCaughtWithoutOn');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught with on clause', () {
    final method = findMethod(unit, 'throwCaughtWithOn');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('ignores throws caught with specific on clause', () {
    final method = findMethod(unit, 'throwCaughtWithSameOn');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('reports throws that are rethrown in catch', () {
    final method = findMethod(unit, 'throwCaughtWithRethrow');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('detects multiple undocumented thrown types', () {
    final method = findMethod(unit, 'undocumentedMultipleThrows');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException', 'MissingFileException'}));
  });

  test('dedupes repeated thrown types', () {
    final method = findMethod(unit, 'duplicatedThrows');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('propagates throws from called methods', () {
    final method = findMethod(unit, 'callerUsesThrowingMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('propagates throws from sdk cache', () {
    final method = findMethod(unit, 'usesRegExp');
    final missing = _missing(
      method.body,
      method.metadata,
      externalLookup: TestThrowsCacheLookup(),
    );

    expect(missing, equals({'FormatException'}));
  });

  test('ignores throws handled after a call', () {
    final method = findMethod(unit, 'callerCatchesThrowingMethod');
    final missing = _missing(
      method.body,
      method.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('detects undocumented thrown types in constructors', () {
    final ctor = findConstructor(unit, className: 'Sample');
    final missing = _missing(
      ctor.body,
      ctor.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts annotated thrown types in named constructors', () {
    final ctor = findConstructor(unit, className: 'Sample', name: 'named');
    final missing = _missing(
      ctor.body,
      ctor.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });

  test('detects undocumented thrown types in top-level functions', () {
    final fn = findFunction(unit, 'undocumentedTopLevel');
    final missing = _missing(
      fn.functionExpression.body,
      fn.metadata,
      allowSourceFallback: true,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('accepts annotated thrown types in top-level functions', () {
    final fn = findFunction(unit, 'documentedTopLevel');
    final missing = _missing(
      fn.functionExpression.body,
      fn.metadata,
      allowSourceFallback: true,
    );

    expect(missing, isEmpty);
  });
}
