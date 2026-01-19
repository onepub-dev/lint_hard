import 'package:analyzer/dart/ast/ast.dart';

import 'document_thrown_exceptions_collector.dart';
import 'document_thrown_exceptions_doc_comments.dart';
import 'document_thrown_exceptions_resolver.dart';
import 'document_thrown_exceptions_type_names.dart';
import 'documentation_style.dart';
import 'throws_cache_lookup.dart';
import 'throwing_annotation.dart';
import 'unit_provider.dart';

class ThrownTypeResults {
  final Set<String> types;
  final List<ThrownTypeInfo> infos;
  final bool sawThrowExpression;
  final bool sawUnknownThrowExpression;

  const ThrownTypeResults(
    this.types,
    this.infos, {
    required this.sawThrowExpression,
    required this.sawUnknownThrowExpression,
  });
}

class ThrownTypeAnalyzer {
  const ThrownTypeAnalyzer();

  // Collect thrown exception types via AST traversal.
  ThrownTypeResults collectThrownTypes(
    FunctionBody body, {
    Map<String, CompilationUnit>? unitsByPath,
    UnitProvider? unitProvider,
    ThrownTypeResolver? resolver,
    ThrowsCacheLookup? externalLookup,
    bool includeLineNumbersForAll = false,
  }) {
    final effectiveUnitProvider = unitProvider ??
        (unitsByPath == null ? null : MapUnitProvider(unitsByPath));
    final effectiveResolver = resolver ??
        (effectiveUnitProvider == null
            ? null
            : ThrownTypeResolver(
                effectiveUnitProvider,
                externalLookup: externalLookup,
                includeLineNumbersForAll: includeLineNumbersForAll,
              ));
    final collector = ThrownTypeCollector(effectiveResolver);
    body.accept(collector);
    return ThrownTypeResults(
      collector.thrownTypes,
      collector.thrownInfos,
      sawThrowExpression: collector.sawThrowExpression,
      sawUnknownThrowExpression: collector.sawUnknownThrowExpression,
    );
  }

  // Find thrown types missing from documentation.
  Set<String> missingThrownTypeDocs(
    FunctionBody body,
    NodeList<Annotation>? metadata, {
    Comment? documentationComment,
    DocumentationStyle documentationStyle = DocumentationStyle.docComment,
    bool allowSourceFallback = false,
    bool honorDocMentions = true,
    Map<String, CompilationUnit>? unitsByPath,
    UnitProvider? unitProvider,
    ThrowsCacheLookup? externalLookup,
    ThrownTypeResults? thrownResults,
  }) {
    final missing = missingThrownTypeInfos(
      body,
      metadata,
      documentationComment: documentationComment,
      documentationStyle: documentationStyle,
      allowSourceFallback: allowSourceFallback,
      honorDocMentions: honorDocMentions,
      unitsByPath: unitsByPath,
      unitProvider: unitProvider,
      externalLookup: externalLookup,
      thrownResults: thrownResults,
    );
    return {for (final info in missing) info.name};
  }

  List<ThrownTypeInfo> missingThrownTypeInfos(
    FunctionBody body,
    NodeList<Annotation>? metadata, {
    Comment? documentationComment,
    DocumentationStyle documentationStyle = DocumentationStyle.docComment,
    bool allowSourceFallback = false,
    bool honorDocMentions = true,
    Map<String, CompilationUnit>? unitsByPath,
    UnitProvider? unitProvider,
    ThrowsCacheLookup? externalLookup,
    bool includeLineNumbersForAll = false,
    ThrownTypeResults? thrownResults,
  }) {
    // Prefer AST; optionally fallback to source parsing for edge cases.
    final effectiveResults =
        thrownResults ??
        collectThrownTypes(
          body,
          unitsByPath: unitsByPath,
          unitProvider: unitProvider,
          externalLookup: externalLookup,
          includeLineNumbersForAll: includeLineNumbersForAll,
        );
    final thrownTypes = effectiveResults.types;
    if (thrownTypes.isEmpty &&
        allowSourceFallback &&
        (effectiveResults.sawUnknownThrowExpression ||
            !effectiveResults.sawThrowExpression)) {
      thrownTypes.addAll(_collectThrownTypesFromSource(body.toSource()));
    }
    if (thrownTypes.isEmpty) return const <ThrownTypeInfo>[];

    final documented = <String>{};
    if (documentationStyle == DocumentationStyle.annotation) {
      documented.addAll(_annotationThrownTypes(metadata));
      if (honorDocMentions) {
        documented.addAll(
          DocCommentAnalyzer().mentionedTypes(documentationComment),
        );
      }
    } else {
      if (honorDocMentions) {
        documented.addAll(
          DocCommentAnalyzer().mentionedTypes(documentationComment),
        );
      } else {
        documented.addAll(
          DocCommentAnalyzer().thrownTypes(documentationComment),
        );
      }
    }
    final byName = <String, ThrownTypeInfo>{};
    for (final info in effectiveResults.infos) {
      final existing = byName[info.name];
      if (existing == null) {
        byName[info.name] = info;
        continue;
      }
      final mergedProvenance = [
        ...existing.provenance,
        ...info.provenance,
      ];
      final mergedType = existing.type ?? info.type;
      byName[info.name] = ThrownTypeInfo(
        info.name,
        mergedType,
        provenance: mergedProvenance,
      );
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
    UnitProvider? unitProvider,
    ThrowsCacheLookup? externalLookup,
  }) {
    return collectThrownTypes(
      body,
      unitsByPath: unitsByPath,
      unitProvider: unitProvider,
      externalLookup: externalLookup,
    ).types;
  }

  List<ThrownTypeInfo> collectThrownTypeInfos(
    FunctionBody body, {
    Map<String, CompilationUnit>? unitsByPath,
    UnitProvider? unitProvider,
    ThrowsCacheLookup? externalLookup,
    bool includeLineNumbersForAll = false,
  }) {
    return collectThrownTypes(
      body,
      unitsByPath: unitsByPath,
      unitProvider: unitProvider,
      externalLookup: externalLookup,
      includeLineNumbersForAll: includeLineNumbersForAll,
    ).infos;
  }
}

const thrownTypeAnalyzer = ThrownTypeAnalyzer();

Set<String> missingThrownTypeDocs(
  FunctionBody body,
  NodeList<Annotation>? metadata, {
  Comment? documentationComment,
  DocumentationStyle documentationStyle = DocumentationStyle.docComment,
  bool allowSourceFallback = false,
  bool honorDocMentions = true,
  Map<String, CompilationUnit>? unitsByPath,
  UnitProvider? unitProvider,
  ThrowsCacheLookup? externalLookup,
  ThrownTypeResults? thrownResults,
}) {
  return thrownTypeAnalyzer.missingThrownTypeDocs(
    body,
    metadata,
    documentationComment: documentationComment,
    documentationStyle: documentationStyle,
    allowSourceFallback: allowSourceFallback,
    honorDocMentions: honorDocMentions,
    unitsByPath: unitsByPath,
    unitProvider: unitProvider,
    externalLookup: externalLookup,
    thrownResults: thrownResults,
  );
}

List<ThrownTypeInfo> missingThrownTypeInfos(
  FunctionBody body,
  NodeList<Annotation>? metadata, {
  Comment? documentationComment,
  DocumentationStyle documentationStyle = DocumentationStyle.docComment,
  bool allowSourceFallback = false,
  bool honorDocMentions = true,
  Map<String, CompilationUnit>? unitsByPath,
  UnitProvider? unitProvider,
  ThrowsCacheLookup? externalLookup,
  bool includeLineNumbersForAll = false,
  ThrownTypeResults? thrownResults,
}) {
  return thrownTypeAnalyzer.missingThrownTypeInfos(
    body,
    metadata,
    documentationComment: documentationComment,
    documentationStyle: documentationStyle,
    allowSourceFallback: allowSourceFallback,
    honorDocMentions: honorDocMentions,
    unitsByPath: unitsByPath,
    unitProvider: unitProvider,
    externalLookup: externalLookup,
    includeLineNumbersForAll: includeLineNumbersForAll,
    thrownResults: thrownResults,
  );
}

Set<String> collectThrownTypeNames(
  FunctionBody body, {
  Map<String, CompilationUnit>? unitsByPath,
  UnitProvider? unitProvider,
  ThrowsCacheLookup? externalLookup,
}) {
  return thrownTypeAnalyzer.collectThrownTypeNames(
    body,
    unitsByPath: unitsByPath,
    unitProvider: unitProvider,
    externalLookup: externalLookup,
  );
}

List<ThrownTypeInfo> collectThrownTypeInfos(
  FunctionBody body, {
  Map<String, CompilationUnit>? unitsByPath,
  UnitProvider? unitProvider,
  ThrowsCacheLookup? externalLookup,
  bool includeLineNumbersForAll = false,
}) {
  return thrownTypeAnalyzer.collectThrownTypeInfos(
    body,
    unitsByPath: unitsByPath,
    unitProvider: unitProvider,
    externalLookup: externalLookup,
    includeLineNumbersForAll: includeLineNumbersForAll,
  );
}

// Extract thrown types from source text as a fallback.
Set<String> _collectThrownTypesFromSource(String source) {
  final matches = RegExp(r'\bthrow\s+([A-Z][A-Za-z0-9_]*)').allMatches(source);
  final types = <String>{};
  for (final match in matches) {
    final name = match.group(1);
    final normalized =
        name == null ? null : typeNameNormalizer.normalizeTypeName(name);
    if (normalized != null) {
      types.add(normalized);
    }
  }
  return types;
}

Set<String> docCommentMentionsWithoutThrows(
  FunctionBody body,
  Comment? comment, {
  Map<String, CompilationUnit>? unitsByPath,
  ThrowsCacheLookup? externalLookup,
}) {
  final mentions = DocCommentAnalyzer().inlineMentionedTypes(comment);
  if (mentions.isEmpty) return const <String>{};
  final thrown = collectThrownTypeNames(
    body,
    unitsByPath: unitsByPath,
    externalLookup: externalLookup,
  );
  return mentions.difference(thrown);
}

Set<String> _annotationThrownTypes(NodeList<Annotation>? metadata) {
  if (metadata == null || metadata.isEmpty) return const <String>{};
  final types = <String>{};
  for (final annotation in metadata) {
    if (_annotationName(annotation) != throwingAnnotationName) continue;
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
  return typeNameNormalizer.normalizeTypeName(expression.toSource());
}
