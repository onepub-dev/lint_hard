import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'document_thrown_exceptions.dart';
import 'throws_cache.dart';

Map<String, List<String>> buildThrowsIndex(
  ResolvedLibraryResult library, {
  String? libraryUri,
}) {
  final unitsByPath = _unitsByPath(library.units);
  final entries = <String, List<String>>{};
  final visitor = _ExecutableIndexCollector(
    libraryUri ?? library.element.firstFragment.source.uri.toString(),
    unitsByPath,
    entries,
  );

  for (final unit in library.units) {
    unit.unit.accept(visitor);
  }

  return entries;
}

class _ExecutableIndexCollector extends RecursiveAstVisitor<void> {
  final String libraryUri;
  final Map<String, CompilationUnit> unitsByPath;
  final Map<String, List<String>> entries;

  _ExecutableIndexCollector(this.libraryUri, this.unitsByPath, this.entries);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final fragment = node.declaredFragment;
    final element = fragment?.element;
    if (element is ExecutableElement) {
      _record(element, node.body);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final fragment = node.declaredFragment;
    final element = fragment?.element;
    if (element is ConstructorElement) {
      _recordConstructor(element, node.body);
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      final fragment = node.declaredFragment;
      final element = fragment?.element;
      if (element is ExecutableElement) {
        _record(element, node.functionExpression.body);
      }
    }
    super.visitFunctionDeclaration(node);
  }

  void _record(ExecutableElement element, FunctionBody body) {
    final thrown = collectThrownTypeNames(
      body,
      unitsByPath: unitsByPath,
    );
    if (thrown.isEmpty) return;
    final key = _keyForExecutable(element);
    entries[key] = thrown.toList()..sort();
  }

  void _recordConstructor(ConstructorElement element, FunctionBody body) {
    final thrown = collectThrownTypeNames(
      body,
      unitsByPath: unitsByPath,
    );
    if (thrown.isEmpty) return;
    final key = _keyForConstructor(element);
    entries[key] = thrown.toList()..sort();
  }

  String _keyForExecutable(ExecutableElement element) {
    final container = _containerName(element.enclosingElement);
    final name = element.name ?? '';
    return ThrowsCacheKeyBuilder.build(
      libraryUri: libraryUri,
      container: container,
      name: name,
      parameterTypes: _parameterTypes(element),
    );
  }

  String _keyForConstructor(ConstructorElement element) {
    final className = element.enclosingElement.name ?? '';
    final ctorElementName = element.name;
    final ctorName = (ctorElementName == null || ctorElementName.isEmpty)
        ? className
        : '$className.$ctorElementName';
    return ThrowsCacheKeyBuilder.build(
      libraryUri: libraryUri,
      container: className,
      name: ctorName,
      parameterTypes: _parameterTypes(element),
    );
  }

  String _containerName(Element? element) {
    if (element is ClassElement) return element.name ?? 'class';
    if (element is MixinElement) return element.name ?? 'mixin';
    if (element is ExtensionElement) return element.name ?? 'extension';
    if (element is InterfaceElement) return element.name ?? 'interface';
    return '_';
  }

  List<String> _parameterTypes(ExecutableElement element) {
    return element.formalParameters
        .map((parameter) => _typeDisplayName(parameter.type))
        .toList();
  }

  String _typeDisplayName(DartType type) {
    if (type is VoidType) return 'void';
    return type.getDisplayString();
  }
}

Map<String, CompilationUnit> _unitsByPath(
  Iterable<ResolvedUnitResult> units,
) {
  final map = <String, CompilationUnit>{};
  for (final unit in units) {
    map[unit.path] = unit.unit;
  }
  return map;
}
