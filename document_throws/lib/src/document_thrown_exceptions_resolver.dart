import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';

import 'document_thrown_exceptions_collector.dart';
import 'document_thrown_exceptions_type_names.dart';
import 'throws_cache.dart';
import 'throws_cache_lookup.dart';
import 'unit_provider.dart';

class ThrownTypeResolver implements ThrownTypeLookup {
  final UnitProvider unitProvider;
  final ThrowsCacheLookup? externalLookup;
  final bool includeLineNumbersForAll;
  final Map<ExecutableElement, List<ThrownTypeInfo>> _cache = {};
  final Set<ExecutableElement> _inProgress = {};
  final Map<String, LineInfo> _lineInfoCache = {};

  ThrownTypeResolver(
    this.unitProvider, {
    ThrowsCacheLookup? externalLookup,
    bool includeLineNumbersForAll = false,
  }) : externalLookup = externalLookup,
       includeLineNumbersForAll = includeLineNumbersForAll;

  @override
  List<ThrownTypeInfo> thrownTypesForExecutable(ExecutableElement element) {
    final cached = _cache[element];
    if (cached != null) return cached;
    if (_inProgress.contains(element)) return const <ThrownTypeInfo>[];
    _inProgress.add(element);

    final infos = <ThrownTypeInfo>[];
    final fragment = element.firstFragment;

    final unit = _unitForFragment(fragment);
    if (unit != null) {
      final node = unit.nodeCovering(offset: fragment.offset);
      final execNode = _executableNodeFrom(node);
      if (execNode != null) {
        final body = execNode.body;
        if (body != null) {
          final collector = ThrownTypeCollector(this);
          body.accept(collector);
          infos.addAll(collector.thrownInfos);
        }
      }
    }
    if (unit == null) {
      final cached = externalLookup?.lookupWithProvenance(element);
      if (cached != null) {
        for (final entry in cached) {
          if (typeNameNormalizer.normalizeTypeName(entry.name) == null) {
            continue;
          }
          infos.add(
            ThrownTypeInfo(
              entry.name,
              null,
              provenance: entry.provenance,
            ),
          );
        }
      }
    }

    _cache[element] = infos;
    _inProgress.remove(element);
    return infos;
  }

  CompilationUnit? _unitForFragment(Fragment fragment) {
    final source = fragment.libraryFragment?.source;
    if (source == null) return null;
    return unitProvider.unitForPath(source.fullName);
  }

  @override
  String keyForExecutable(ExecutableElement element) {
    final libraryUri = element.library.firstFragment.source.uri.toString();
    final baseKey = _keyForExecutableElement(element, libraryUri);
    final includeLine =
        includeLineNumbersForAll || _unitForFragment(element.firstFragment) == null;
    if (!includeLine) return baseKey;
    final line = _lineNumberForElement(element);
    return line == null ? baseKey : '$baseKey:$line';
  }

  int? _lineNumberForElement(ExecutableElement element) {
    final source = element.library.firstFragment.source;
    final path = source.fullName;
    final lineInfo = _lineInfoCache.putIfAbsent(path, () {
      final content = source.contents.data;
      return LineInfo.fromContent(content);
    });
    final offset = element.firstFragment.offset;
    return lineInfo.getLocation(offset).lineNumber;
  }
}

String _keyForExecutableElement(ExecutableElement element, String libraryUri) {
  if (element is ConstructorElement) {
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

  final container = _containerName(element.enclosingElement);
  final name = element.name ?? '';
  return ThrowsCacheKeyBuilder.build(
    libraryUri: libraryUri,
    container: container,
    name: name,
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

_ExecutableNode? _executableNodeFrom(AstNode? node) {
  final method = node?.thisOrAncestorOfType<MethodDeclaration>();
  if (method != null) {
    return _ExecutableNode(method.body);
  }
  final ctor = node?.thisOrAncestorOfType<ConstructorDeclaration>();
  if (ctor != null) {
    return _ExecutableNode(ctor.body);
  }
  final function = node?.thisOrAncestorOfType<FunctionDeclaration>();
  if (function != null && function.parent is CompilationUnit) {
    return _ExecutableNode(function.functionExpression.body);
  }
  return null;
}

class _ExecutableNode {
  final FunctionBody? body;

  const _ExecutableNode(this.body);
}
