import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'document_thrown_exceptions_type_names.dart';
import 'throws_cache.dart';

class ThrownTypeInfo {
  final String name;
  final DartType? type;
  final List<ThrowsProvenance> provenance;

  const ThrownTypeInfo(
    this.name,
    this.type, {
    this.provenance = const [],
  });
}

abstract class ThrownTypeLookup {
  String keyForExecutable(ExecutableElement element);
  List<ThrownTypeInfo> thrownTypesForExecutable(ExecutableElement element);
}

class ThrownTypeCollector extends RecursiveAstVisitor<void> {
  final ThrownTypeLookup? resolver;
  final Map<String, ThrownTypeInfo> _thrownByName = {};
  final Map<String, Set<String>> _provenanceKeysByName = {};
  final Set<String> thrownTypes = <String>{};
  bool sawThrowExpression = false;
  int _unknownThrowCount = 0;

  ThrownTypeCollector(this.resolver);

  bool get sawUnknownThrowExpression => _unknownThrowCount > 0;

  List<ThrownTypeInfo> get thrownInfos => _thrownByName.values.toList();

  @override
  // Record exception types from throw expressions.
  void visitThrowExpression(ThrowExpression node) {
    sawThrowExpression = true;
    final info = _thrownTypeFromExpression(node.expression);
    if (info != null) {
      _recordThrow(info);
    } else {
      _unknownThrowCount++;
    }
    super.visitThrowExpression(node);
  }

  @override
  // Include exceptions from invoked methods/constructors when resolvable.
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (element is ExecutableElement) {
      _addInvokedThrows(element);
    }
    super.visitMethodInvocation(node);
  }

  @override
  // Include exceptions from function-typed invocations when resolvable.
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _addInvokedThrows(node.element);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  // Include exceptions from constructors when resolvable.
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _addInvokedThrows(node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  // Skip throws caught by a try/catch without rethrowing.
  void visitTryStatement(TryStatement node) {
    final bodyCollector = ThrownTypeCollector(resolver);
    node.body.accept(bodyCollector);

    for (final info in bodyCollector._thrownByName.values) {
      if (!_isCaughtWithoutRethrow(info, node.catchClauses)) {
        if (!_catchListHandlesName(node.catchClauses, info.name)) {
          _recordThrow(info);
        }
      }
    }

    if (bodyCollector.sawThrowExpression) {
      sawThrowExpression = true;
    }
    if (bodyCollector._unknownThrowCount > 0 &&
        !_catchesAllWithoutRethrow(node.catchClauses)) {
      _unknownThrowCount += bodyCollector._unknownThrowCount;
    }

    for (final clause in node.catchClauses) {
      clause.body.accept(this);
    }
    node.finallyBlock?.accept(this);
  }

  void _recordThrow(ThrownTypeInfo info) {
    thrownTypes.add(info.name);
    final existing = _thrownByName[info.name];
    if (existing == null) {
      final provenance = _dedupeProvenance(info.name, info.provenance);
      _thrownByName[info.name] = ThrownTypeInfo(
        info.name,
        info.type,
        provenance: provenance,
      );
      return;
    }
    final mergedType = existing.type ?? info.type;
    final mergedProvenance = <ThrowsProvenance>[
      ...existing.provenance,
      ..._dedupeProvenance(info.name, info.provenance),
    ];
    _thrownByName[info.name] = ThrownTypeInfo(
      info.name,
      mergedType,
      provenance: mergedProvenance,
    );
  }

  List<ThrowsProvenance> _dedupeProvenance(
    String name,
    List<ThrowsProvenance> provenance,
  ) {
    if (provenance.isEmpty) return const <ThrowsProvenance>[];
    final seen = _provenanceKeysByName.putIfAbsent(name, () => <String>{});
    final deduped = <ThrowsProvenance>[];
    for (final entry in provenance) {
      final key = '${entry.call}|${entry.origin ?? ''}';
      if (seen.add(key)) {
        deduped.add(entry);
      }
    }
    return deduped;
  }

  void _addInvokedThrows(ExecutableElement? element) {
    if (element == null || resolver == null) return;
    final callKey = resolver!.keyForExecutable(element);
    final invoked = resolver!.thrownTypesForExecutable(element);
    for (final info in invoked) {
      _recordThrow(_applyCallProvenance(info, callKey));
    }
  }

  bool _isCaughtWithoutRethrow(
    ThrownTypeInfo info,
    NodeList<CatchClause> catchClauses,
  ) {
    for (final clause in catchClauses) {
      if (_catchMatches(info, clause)) {
        return !_catchRethrows(clause);
      }
    }
    return false;
  }

  bool _catchMatches(ThrownTypeInfo info, CatchClause clause) {
    final exceptionType = clause.exceptionType;
    if (exceptionType == null) return true;

    final catchType = exceptionType.type;
    if (catchType != null && info.type != null) {
      if (_isSubtypeOf(info.type!, catchType)) return true;
    }

    final catchName = typeNameNormalizer.catchTypeName(exceptionType);
    if (catchName == null) return false;
    if (_isCatchAllName(catchName, info.name)) return true;
    if (catchName == info.name) return true;
    return false;
  }

  bool _isSubtypeOf(DartType thrownType, DartType catchType) {
    if (thrownType is InterfaceType && catchType is InterfaceType) {
      if (thrownType.element == catchType.element) return true;
      for (final supertype in thrownType.allSupertypes) {
        if (supertype.element == catchType.element) return true;
      }
    }
    return false;
  }

  bool _catchRethrows(CatchClause clause) {
    final finder = _RethrowFinder();
    clause.body.accept(finder);
    return finder.found;
  }

  bool _catchesAllWithoutRethrow(NodeList<CatchClause> catchClauses) {
    for (final clause in catchClauses) {
      if (_catchRethrows(clause)) continue;
      final exceptionType = clause.exceptionType;
      if (exceptionType == null) return true;
      final catchName = typeNameNormalizer.normalizeCatchTypeName(
        exceptionType.toSource(),
      );
      if (catchName == null) continue;
      if (catchName == 'Object' ||
          catchName == 'dynamic' ||
          catchName == 'Exception' ||
          catchName == 'Error') {
        return true;
      }
    }
    return false;
  }

  bool _catchListHandlesName(
    NodeList<CatchClause> catchClauses,
    String thrownName,
  ) {
    for (final clause in catchClauses) {
      if (_catchRethrows(clause)) continue;
      final exceptionType = clause.exceptionType;
      if (exceptionType == null) return true;
      final catchName = typeNameNormalizer.normalizeCatchTypeName(
        exceptionType.toSource(),
      );
      if (catchName == null) continue;
      if (_isCatchAllName(catchName, thrownName)) return true;
    }
    return false;
  }
}

ThrownTypeInfo _applyCallProvenance(
  ThrownTypeInfo info,
  String callKey,
) {
  if (info.provenance.isEmpty) {
    return ThrownTypeInfo(
      info.name,
      info.type,
      provenance: [ThrowsProvenance(call: callKey, origin: null)],
    );
  }
  final provenance = <ThrowsProvenance>[];
  for (final entry in info.provenance) {
    final origin = entry.origin ?? entry.call;
    provenance.add(
      ThrowsProvenance(
        call: callKey,
        origin: origin == callKey ? null : origin,
      ),
    );
  }
  return ThrownTypeInfo(
    info.name,
    info.type,
    provenance: provenance,
  );
}

class _RethrowFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitRethrowExpression(RethrowExpression node) {
    found = true;
  }
}

// Normalize a thrown expression into a type name and type, if available.
ThrownTypeInfo? _thrownTypeFromExpression(Expression expression) {
  if (expression is InstanceCreationExpression) {
    final staticType = expression.staticType;
    if (staticType is InvalidType) return null;
    final typeName = expression.constructorName.type.name.lexeme;
    final normalized = typeNameNormalizer.normalizeTypeName(typeName);
    if (normalized == null) return null;
    return ThrownTypeInfo(normalized, expression.staticType);
  }

  final staticType = expression.staticType;
  if (staticType == null) return null;
  if (staticType is InvalidType) return null;

  final displayName = staticType.getDisplayString();
  final normalized = typeNameNormalizer.normalizeTypeName(displayName);
  if (normalized == null) return null;
  return ThrownTypeInfo(normalized, staticType);
}

bool _isCatchAllName(String catchName, String thrownName) {
  if (catchName == 'Object' || catchName == 'dynamic') return true;
  if (catchName == 'Exception') return thrownName.endsWith('Exception');
  if (catchName == 'Error') return thrownName.endsWith('Error');
  return false;
}
