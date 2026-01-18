import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:document_throws/src/document_thrown_exceptions.dart';
import 'package:test/test.dart';

void main() {
  late CompilationUnit unit;
  late ResolvedUnitResult resolvedUnit;
  late ResolvedLibraryResult resolvedLibrary;
  late Map<String, CompilationUnit> unitsByPath;

  setUpAll(() async {
    final fixturePath = 'test/fixtures/propagation_thrown_exceptions.dart';
    final filePath = File(fixturePath).absolute.path;
    final resolved = await _resolveFixture(filePath);
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
  }) {
    return missingThrownTypeDocs(
      body,
      metadata,
      allowSourceFallback: allowSourceFallback,
      unitsByPath: unitsByPath,
    );
  }

  test('propagates throws from top-level functions', () {
    final method = _method(unit, 'callsTopLevel');
    final missing = _missing(
      method.body,
      method.metadata,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('propagates throws from instance methods', () {
    final method = _method(unit, 'callsMethod');
    final missing = _missing(
      method.body,
      method.metadata,
    );

    expect(missing, equals({'BadStateException'}));
  });

  test('propagates throws from constructors', () {
    final method = _method(unit, 'callsCtor');
    final missing = _missing(
      method.body,
      method.metadata,
    );

    expect(missing, equals({'MissingFileException'}));
  });

  test('ignores throws handled by parent-type catch', () {
    final method = _method(unit, 'catchesParent');
    final missing = _missing(
      method.body,
      method.metadata,
    );

    expect(missing, isEmpty);
  });

  test('propagates throws from part files', () {
    final method = _method(unit, 'usesPartFunction');
    final missing = _missing(
      method.body,
      method.metadata,
    );

    expect(missing, equals({'MissingFileException'}));
  });

  // TODO: doc-based propagation disabled; re-enable if docs are used again.
  // test('propagates throws from documented callees', () {
  //   final method = _method(unit, 'callsDocThrower');
  //   final missing = _missing(
  //     method.body,
  //     method.documentationComment,
  //   );
  //
  //   expect(missing, equals({'BadStateException'}));
  // });
  //
  // test('propagates multiple throws from documented callees', () {
  //   final method = _method(unit, 'callsMultiDocThrower');
  //   final missing = _missing(
  //     method.body,
  //     method.documentationComment,
  //   );
  //
  //   expect(missing, equals({'BadStateException', 'MissingFileException'}));
  // });

  test('propagates throws from local functions', () {
    final method = _method(unit, 'callsLocalFunction');
    final missing = _missing(
      method.body,
      method.metadata,
    );

    expect(missing, equals({'BadStateException'}));
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
