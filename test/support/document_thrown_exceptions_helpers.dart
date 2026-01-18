import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:lint_hard/src/throws_cache.dart';
import 'package:lint_hard/src/throws_cache_lookup.dart';

class ResolvedFixture {
  final ResolvedUnitResult unit;
  final ResolvedLibraryResult library;

  const ResolvedFixture(this.unit, this.library);
}

Future<ResolvedFixture> resolveFixture(String filePath) async {
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
  return ResolvedFixture(unitResult, libraryResult);
}

MethodDeclaration findMethod(CompilationUnit unit, String name) {
  final finder = _MethodFinder(name);
  unit.accept(finder);
  final method = finder.found;
  if (method == null) {
    throw StateError('Method not found: $name');
  }
  return method;
}

ConstructorDeclaration findConstructor(
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

FunctionDeclaration findFunction(CompilationUnit unit, String name) {
  final finder = _FunctionFinder(name);
  unit.accept(finder);
  final fn = finder.found;
  if (fn == null) {
    throw StateError('Function not found: $name');
  }
  return fn;
}

class TestThrowsCacheLookup extends ThrowsCacheLookup {
  TestThrowsCacheLookup()
    : super(
        cache: ThrowsCache(Directory.systemTemp.path),
        packageVersions: const {},
        packageSources: const {},
        sdkVersion: 'test',
        sdkRoot: null,
        flutterVersion: null,
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

  @override
  List<CachedThrownType> lookupWithProvenance(ExecutableElement element) {
    final uri = element.library.firstFragment.source.uri.toString();
    if (uri == 'dart:core' &&
        element is ConstructorElement &&
        element.enclosingElement.name == 'RegExp') {
      return const [CachedThrownType('FormatException')];
    }
    return const <CachedThrownType>[];
  }
}

class ProvenanceThrowsCacheLookup extends ThrowsCacheLookup {
  ProvenanceThrowsCacheLookup()
    : super(
        cache: ThrowsCache(Directory.systemTemp.path),
        packageVersions: const {},
        packageSources: const {},
        sdkVersion: 'test',
        sdkRoot: null,
        flutterVersion: null,
      );

  @override
  List<CachedThrownType> lookupWithProvenance(ExecutableElement element) {
    final uri = element.library.firstFragment.source.uri.toString();
    if (uri == 'dart:core' &&
        element is ConstructorElement &&
        element.enclosingElement.name == 'RegExp') {
      return const [
        CachedThrownType(
          'FormatException',
          provenance: [
            ThrowsProvenance(
              call: 'dart:core|RegExp#RegExp():10',
              origin: 'dart:core|RegExp#RegExp():999',
            ),
          ],
        ),
      ];
    }
    return const <CachedThrownType>[];
  }
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
