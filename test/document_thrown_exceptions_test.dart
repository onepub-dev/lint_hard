import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:lint_hard/src/document_thrown_exceptions.dart';
import 'package:test/test.dart';

void main() {
  late CompilationUnit unit;

  setUpAll(() {
    final content =
        File('test/fixtures/document_thrown_exceptions.dart').readAsStringSync();
    unit = parseString(content: content).unit;
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
