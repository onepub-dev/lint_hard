import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'throws_cache_lookup.dart';

class DocumentThrownExceptions extends AnalysisRule {
  static const LintCode code = LintCode(
    'document_thrown_exceptions',
    'Document thrown exception types with @Throws. Missing: {0}.',
    correctionMessage:
        'Add @Throws(ExceptionType) for each thrown exception class.',
  );

  // Configure the lint rule metadata.
  DocumentThrownExceptions()
    : super(
        name: code.name,
        description:
            'Require @Throws annotations for each exception class thrown by a '
            'method.',
      );

  @override
  // Expose lint code for registration and fixes.
  LintCode get diagnosticCode => code;

  @override
  // Register visitors that inspect executable members.
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addConstructorDeclaration(this, visitor)
      ..addFunctionDeclaration(this, visitor)
      ..addMethodDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;
  final Map<String, CompilationUnit> unitsByPath;
  final ThrowsCacheLookup? externalLookup;

  // Hold the rule to report diagnostics.
  _Visitor(this.rule, this.context)
    : unitsByPath = _unitsByPathFromContext(context),
      externalLookup = _throwsCacheLookupFromContext(context);

  @override
  // Inspect method bodies for undocumented throw types.
  void visitMethodDeclaration(MethodDeclaration node) {
    _checkExecutable(
      body: node.body,
      metadata: node.metadata,
      reportToken: node.name,
    );
  }

  @override
  // Inspect constructor bodies for undocumented throw types.
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _checkExecutable(
      body: node.body,
      metadata: node.metadata,
      reportToken: node.returnType.beginToken,
    );
  }

  @override
  // Inspect top-level functions only (skip local/anonymous).
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is! CompilationUnit) return;
    _checkExecutable(
      body: node.functionExpression.body,
      metadata: node.metadata,
      reportToken: node.name,
    );
  }

  void _checkExecutable({
    required FunctionBody body,
    required NodeList<Annotation>? metadata,
    required Token reportToken,
  }) {
    // Fast exit when no throw token appears in the body.
    if (body is EmptyFunctionBody) return;

    // Report when any thrown types are missing from docs.
    final missing = missingThrownTypeDocs(
      body,
      metadata,
      unitsByPath: unitsByPath,
      externalLookup: externalLookup,
    );
    if (missing.isEmpty) return;

    final missingList = missing.toList()..sort();
    final missingLabel = missingList.join(', ');
    rule.reportAtToken(reportToken, arguments: [missingLabel]);
  }
}

// Collect thrown exception types via AST traversal.
_ThrownTypeResults _collectThrownTypes(
  FunctionBody body, {
  Map<String, CompilationUnit>? unitsByPath,
  _ThrownTypeResolver? resolver,
  ThrowsCacheLookup? externalLookup,
}) {
  final effectiveResolver =
      resolver ??
      (unitsByPath == null
          ? null
          : _ThrownTypeResolver(unitsByPath, externalLookup: externalLookup));
  final collector = _ThrowTypeCollector(effectiveResolver);
  body.accept(collector);
  return _ThrownTypeResults(
    collector.thrownTypes,
    collector._thrown,
    sawThrowExpression: collector.sawThrowExpression,
    sawUnknownThrowExpression: collector.sawUnknownThrowExpression,
  );
}

class _ThrownTypeResults {
  final Set<String> types;
  final List<ThrownTypeInfo> infos;
  final bool sawThrowExpression;
  final bool sawUnknownThrowExpression;

  const _ThrownTypeResults(
    this.types,
    this.infos, {
    required this.sawThrowExpression,
    required this.sawUnknownThrowExpression,
  });
}

// Find thrown types missing from documentation.
Set<String> missingThrownTypeDocs(
  FunctionBody body,
  NodeList<Annotation>? metadata, {
  bool allowSourceFallback = false,
  Map<String, CompilationUnit>? unitsByPath,
  ThrowsCacheLookup? externalLookup,
}) {
  final missing = missingThrownTypeInfos(
    body,
    metadata,
    allowSourceFallback: allowSourceFallback,
    unitsByPath: unitsByPath,
    externalLookup: externalLookup,
  );
  return {for (final info in missing) info.name};
}

List<ThrownTypeInfo> missingThrownTypeInfos(
  FunctionBody body,
  NodeList<Annotation>? metadata, {
  bool allowSourceFallback = false,
  Map<String, CompilationUnit>? unitsByPath,
  ThrowsCacheLookup? externalLookup,
}) {
  // Prefer AST; optionally fallback to source parsing for edge cases.
  final thrownResults = _collectThrownTypes(
    body,
    unitsByPath: unitsByPath,
    externalLookup: externalLookup,
  );
  final thrownTypes = thrownResults.types;
  if (thrownTypes.isEmpty &&
      allowSourceFallback &&
      (thrownResults.sawUnknownThrowExpression ||
          !thrownResults.sawThrowExpression)) {
    thrownTypes.addAll(_collectThrownTypesFromSource(body.toSource()));
  }
  if (thrownTypes.isEmpty) return const <ThrownTypeInfo>[];

  final documented = _annotationThrownTypes(metadata);
  final byName = <String, ThrownTypeInfo>{};
  for (final info in thrownResults.infos) {
    final existing = byName[info.name];
    if (existing == null || (existing.type == null && info.type != null)) {
      byName[info.name] = info;
    }
  }
  for (final name in thrownTypes) {
    byName.putIfAbsent(name, () => ThrownTypeInfo(name, null));
  }

  final missing = <ThrownTypeInfo>[];
  for (final entry in byName.entries) {
    if (!documented.contains(entry.key)) {
      missing.add(entry.value);
    }
  }
  return missing;
}

Set<String> collectThrownTypeNames(
  FunctionBody body, {
  Map<String, CompilationUnit>? unitsByPath,
  ThrowsCacheLookup? externalLookup,
}) {
  return _collectThrownTypes(
    body,
    unitsByPath: unitsByPath,
    externalLookup: externalLookup,
  ).types;
}

// Extract thrown types from source text as a fallback.
Set<String> _collectThrownTypesFromSource(String source) {
  final matches = RegExp(r'\bthrow\s+([A-Z][A-Za-z0-9_]*)').allMatches(source);
  final types = <String>{};
  for (final match in matches) {
    final name = match.group(1);
    final normalized = name == null ? null : _normalizeTypeName(name);
    if (normalized != null) {
      types.add(normalized);
    }
  }
  return types;
}

Set<String> _annotationThrownTypes(NodeList<Annotation>? metadata) {
  if (metadata == null || metadata.isEmpty) return const <String>{};
  final types = <String>{};
  for (final annotation in metadata) {
    if (_annotationName(annotation) != 'Throws') continue;
    final args = annotation.arguments?.arguments;
    if (args == null || args.isEmpty) continue;
    final first = args.first;
    if (first is ListLiteral) continue;
    final normalized = _extractThrowTypeName(first);
    if (normalized != null) {
      types.add(normalized);
    }
  }
  return types;
}

String? _annotationName(Annotation annotation) {
  final name = annotation.name;
  if (name is SimpleIdentifier) return name.name;
  if (name is PrefixedIdentifier) return name.identifier.name;
  return null;
}

String? _extractThrowTypeName(Expression expression) {
  return _normalizeTypeName(expression.toSource());
}

class ThrownTypeInfo {
  final String name;
  final DartType? type;

  const ThrownTypeInfo(this.name, this.type);
}

class _ThrowTypeCollector extends RecursiveAstVisitor<void> {
  final _ThrownTypeResolver? _resolver;
  final List<ThrownTypeInfo> _thrown = [];
  final Set<String> thrownTypes = <String>{};
  bool sawThrowExpression = false;
  int _unknownThrowCount = 0;

  _ThrowTypeCollector(this._resolver);

  bool get sawUnknownThrowExpression => _unknownThrowCount > 0;

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
    final bodyCollector = _ThrowTypeCollector(_resolver);
    node.body.accept(bodyCollector);

    for (final info in bodyCollector._thrown) {
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
    _thrown.add(info);
    thrownTypes.add(info.name);
  }

  void _addInvokedThrows(ExecutableElement? element) {
    if (element == null || _resolver == null) return;
    final invoked = _resolver.thrownTypesForExecutable(element);
    for (final info in invoked) {
      _recordThrow(info);
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

    final catchName = _catchTypeName(exceptionType);
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
      final catchName = _normalizeCatchTypeName(exceptionType.toSource());
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
      final catchName = _normalizeCatchTypeName(exceptionType.toSource());
      if (catchName == null) continue;
      if (_isCatchAllName(catchName, thrownName)) return true;
    }
    return false;
  }
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
    final typeName = expression.constructorName.type.name.lexeme;
    final normalized = _normalizeTypeName(typeName);
    if (normalized == null) return null;
    return ThrownTypeInfo(normalized, expression.staticType);
  }

  final staticType = expression.staticType;
  if (staticType == null) return null;

  final displayName = staticType.getDisplayString();
  final normalized = _normalizeTypeName(displayName);
  if (normalized == null) return null;
  return ThrownTypeInfo(normalized, staticType);
}

// Strip generics/qualifiers and drop non-specific types.
String? _normalizeTypeName(String rawName) {
  var name = rawName.trim();
  if (name.isEmpty) return null;

  final genericSplit = name.split('<');
  name = genericSplit.first;

  final dotIndex = name.lastIndexOf('.');
  if (dotIndex != -1) {
    name = name.substring(dotIndex + 1);
  }

  if (name == 'dynamic' || name == 'Object' || name == 'Never') return null;
  return name;
}

String? _normalizeCatchTypeName(String rawName) {
  var name = rawName.trim();
  if (name.isEmpty) return null;

  name = name.split(RegExp(r'\s+')).first;

  if (name.endsWith('?')) {
    name = name.substring(0, name.length - 1);
  }

  final genericSplit = name.split('<');
  name = genericSplit.first;

  final dotIndex = name.lastIndexOf('.');
  if (dotIndex != -1) {
    name = name.substring(dotIndex + 1);
  }

  return name;
}

String? _catchTypeName(TypeAnnotation exceptionType) {
  if (exceptionType is NamedType) {
    return _normalizeCatchTypeName(exceptionType.name.lexeme);
  }
  return _normalizeCatchTypeName(exceptionType.toSource());
}

class _ThrownTypeResolver {
  final Map<String, CompilationUnit> _unitsByPath;
  final ThrowsCacheLookup? _externalLookup;
  final Map<ExecutableElement, List<ThrownTypeInfo>> _cache = {};
  final Set<ExecutableElement> _inProgress = {};

  _ThrownTypeResolver(this._unitsByPath, {ThrowsCacheLookup? externalLookup})
    : _externalLookup = externalLookup;

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
          final thrownResults = _collectThrownTypes(body, resolver: this);
          infos.addAll(thrownResults.infos);
        }
      }
    }
    if (unit == null) {
      final cached = _externalLookup?.lookup(element) ?? const <String>[];
      for (final name in cached) {
        infos.add(ThrownTypeInfo(name, null));
      }
    }

    _cache[element] = infos;
    _inProgress.remove(element);
    return infos;
  }

  CompilationUnit? _unitForFragment(Fragment fragment) {
    final source = fragment.libraryFragment?.source;
    if (source == null) return null;
    return _unitsByPath[source.fullName];
  }
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

Map<String, CompilationUnit> _unitsByPathFromContext(RuleContext context) {
  final map = <String, CompilationUnit>{};
  for (final unit in context.allUnits) {
    map[unit.file.path] = unit.unit;
  }
  return map;
}

ThrowsCacheLookup? _throwsCacheLookupFromContext(RuleContext context) {
  final root = context.package?.root.path;
  if (root == null) return null;
  return ThrowsCacheLookup.forProjectRoot(root);
}

// Doc-based discovery is intentionally disabled in favor of @Throws.

bool _isCatchAllName(String catchName, String thrownName) {
  if (catchName == 'Object' || catchName == 'dynamic') return true;
  if (catchName == 'Exception') return thrownName.endsWith('Exception');
  if (catchName == 'Error') return thrownName.endsWith('Error');
  return false;
}
