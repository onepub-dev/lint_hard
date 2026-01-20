import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:path/path.dart' as p;

import 'document_thrown_exceptions.dart';
import 'documentation_style.dart';
import 'throws_cache.dart';
import 'throws_cache_lookup.dart';
import 'throwing_annotation.dart';

Map<String, List<SourceEdit>> documentThrownExceptionEdits(
  ResolvedUnitResult unitResult,
  Iterable<ResolvedUnitResult> libraryUnits, {
  ThrowsCacheLookup? externalLookup,
  bool includeSource = false,
  bool honorDocMentions = true,
  DocumentationStyle documentationStyle = DocumentationStyle.docComment,
  ExecutableTarget? onlyTarget,
}) {
  final unitsByPath = unitsByPathFromResolvedUnits(libraryUnits);
  final collector = _ExecutableCollector();
  unitResult.unit.accept(collector);

  final content = unitResult.content;
  final editsByPath = <String, List<SourceEdit>>{};
  final importTarget = _importTargetUnit(unitResult, libraryUnits);
  var hasImport = _hasThrowsImport(importTarget.unit);
  final targets = onlyTarget == null
      ? collector.targets
      : collector.targets.where(
          (target) => target.declarationOffset == onlyTarget.declarationOffset,
        );
  for (final target in targets) {
    final hasThrowingAnnotations = _hasThrowingAnnotations(target.metadata);
    final hasDocThrowingTags = _hasDocThrowingTags(
      target.documentationComment,
    );
    var removeOtherStyle = documentationStyle == DocumentationStyle.docComment
        ? hasThrowingAnnotations
        : hasDocThrowingTags;
    final needsProvenanceCleanup =
        !includeSource &&
        (documentationStyle == DocumentationStyle.annotation
            ? _hasProvenanceAnnotations(target.metadata)
            : _hasProvenanceDocTags(target.documentationComment));
    final thrownInfos = includeSource || needsProvenanceCleanup
        ? _mergeThrownInfos(
            collectThrownTypeInfos(
              target.body,
              unitsByPath: unitsByPath,
              externalLookup: externalLookup,
            ),
          )
        : missingThrownTypeInfos(
            target.body,
            target.metadata,
            documentationComment: target.documentationComment,
            documentationStyle: documentationStyle,
            honorDocMentions: honorDocMentions,
            unitsByPath: unitsByPath,
            externalLookup: externalLookup,
          );
    if (documentationStyle == DocumentationStyle.annotation &&
        honorDocMentions &&
        thrownInfos.isEmpty) {
      removeOtherStyle = false;
    }
    if (thrownInfos.isEmpty && !removeOtherStyle) continue;

    final commentStyle = documentationStyle == DocumentationStyle.docComment
        ? _docCommentStyle(target.documentationComment)
        : _DocCommentStyle.none;
    final insertOffset = documentationStyle == DocumentationStyle.annotation
        ? _annotationInsertOffset(content, target)
        : _docCommentInsertOffset(content, target, commentStyle);
    final indent = documentationStyle == DocumentationStyle.docComment &&
            target.documentationComment != null
        ? indentAtOffset(content, target.documentationComment!.offset)
        : indentAtOffset(content, target.declarationOffset);
    final libraryUri = unitResult.libraryFragment.source.uri.toString();
    final importData = _collectImportPrefixes(importTarget.unit);
    final sortedMissing = thrownInfos.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final reasonByType = includeSource || needsProvenanceCleanup
        ? documentationStyle == DocumentationStyle.annotation
            ? _annotationReasonByType(target.metadata)
            : _docCommentReasonByType(target.documentationComment)
        : const <String, String>{};
    final lines = <String>[];
    final rawDocLines = <String>[];
    const lineLimit = 80;
    final prefixLength = documentationStyle == DocumentationStyle.docComment
        ? (commentStyle == _DocCommentStyle.block ? 2 : 4)
        : 0;
    var maxLineLength = lineLimit - indent.length - prefixLength;
    if (maxLineLength < 20) {
      maxLineLength = 20;
    }
    for (final info in sortedMissing) {
      final rendered = _formatThrownAnnotations(
        info,
        importData,
        libraryUri,
        includeSource: includeSource,
        reasonSource: reasonByType[info.name],
        unit: importTarget.unit,
        maxLineLength: maxLineLength,
      );
      rawDocLines.addAll(rendered);
      final displayLines = documentationStyle == DocumentationStyle.docComment
          ? _prefixDocCommentLines(rendered, commentStyle)
          : rendered;
      lines.addAll(displayLines);
    }
    final replaceDocComment = documentationStyle ==
            DocumentationStyle.docComment &&
        target.documentationComment != null &&
        (includeSource || needsProvenanceCleanup);
    if (replaceDocComment) {
      final updated = _replaceDocThrowingTags(
        content,
        target.documentationComment!,
        rawDocLines,
        indent,
        commentStyle,
      );
      _addEdit(
        editsByPath,
        unitResult.path,
        SourceEdit(
          target.documentationComment!.offset,
          target.documentationComment!.end -
              target.documentationComment!.offset,
          updated,
        ),
      );
    } else {
      if (includeSource || needsProvenanceCleanup) {
        if (documentationStyle == DocumentationStyle.annotation) {
          final removeEdits = _removeThrowsAnnotations(
            content,
            target.metadata,
            sortedMissing.map((info) => info.name).toSet(),
          );
          _addEdits(editsByPath, unitResult.path, removeEdits);
        } else {
          final removeEdits = _removeDocThrowingTags(
            content,
            target.documentationComment,
          );
          _addEdits(editsByPath, unitResult.path, removeEdits);
        }
      }
      if (removeOtherStyle) {
        if (documentationStyle == DocumentationStyle.annotation) {
          final removeEdits = _removeDocThrowingTags(
            content,
            target.documentationComment,
          );
          _addEdits(editsByPath, unitResult.path, removeEdits);
        } else {
          final removeEdits = _removeThrowsAnnotations(
            content,
            target.metadata,
            _annotationThrownTypes(target.metadata),
          );
          _addEdits(editsByPath, unitResult.path, removeEdits);
        }
      }
      final insertionText = _renderInsertionText(
        indent,
        lines,
        documentationStyle,
        commentStyle,
      );
      if (insertionText != null) {
        _addEdit(
          editsByPath,
          unitResult.path,
          SourceEdit(insertOffset, 0, insertionText),
        );
      }
    }
    if (documentationStyle == DocumentationStyle.annotation && !hasImport) {
      final insertion = _importInsertion(
        importTarget.unit,
        importTarget.content,
      );
      _addEdit(
        editsByPath,
        importTarget.path,
        SourceEdit(insertion.offset, 0, insertion.text),
      );
      hasImport = true;
    }
  }

  return editsByPath;
}

ExecutableTarget? findExecutableTarget(AstNode node) {
  final method = node.thisOrAncestorOfType<MethodDeclaration>();
  if (method != null) {
    return ExecutableTarget(
      body: method.body,
      metadata: method.metadata,
      declarationOffset: method.offset,
      documentationComment: method.documentationComment,
    );
  }

  final ctor = node.thisOrAncestorOfType<ConstructorDeclaration>();
  if (ctor != null) {
    return ExecutableTarget(
      body: ctor.body,
      metadata: ctor.metadata,
      declarationOffset: ctor.offset,
      documentationComment: ctor.documentationComment,
    );
  }

  final function = node.thisOrAncestorOfType<FunctionDeclaration>();
  if (function != null && function.parent is CompilationUnit) {
    return ExecutableTarget(
      body: function.functionExpression.body,
      metadata: function.metadata,
      declarationOffset: function.offset,
      documentationComment: function.documentationComment,
    );
  }

  return null;
}

int lineStart(String content, int offset) {
  var i = offset - 1;
  while (i >= 0) {
    final ch = content.codeUnitAt(i);
    if (ch == 0x0A) return i + 1; // \n
    if (ch == 0x0D) {
      final isCrLf =
          (i + 1 < content.length) && content.codeUnitAt(i + 1) == 0x0A;
      return isCrLf ? i + 2 : i + 1;
    }
    i--;
  }
  return 0;
}

String indentAtOffset(String content, int offset) {
  final start = lineStart(content, offset);
  var i = start;
  while (i < offset) {
    final ch = content.codeUnitAt(i);
    if (ch != 0x20 && ch != 0x09) break; // space or tab
    i++;
  }
  return content.substring(start, i);
}

class ExecutableTarget {
  final FunctionBody body;
  final NodeList<Annotation>? metadata;
  final int declarationOffset;
  final Comment? documentationComment;

  ExecutableTarget({
    required this.body,
    required this.metadata,
    required this.declarationOffset,
    required this.documentationComment,
  });
}

void _addEdits(
  Map<String, List<SourceEdit>> editsByPath,
  String path,
  List<SourceEdit> edits,
) {
  if (edits.isEmpty) return;
  editsByPath.putIfAbsent(path, () => <SourceEdit>[]).addAll(edits);
}

void _addEdit(
  Map<String, List<SourceEdit>> editsByPath,
  String path,
  SourceEdit edit,
) {
  editsByPath.putIfAbsent(path, () => <SourceEdit>[]).add(edit);
}

ResolvedUnitResult _importTargetUnit(
  ResolvedUnitResult unitResult,
  Iterable<ResolvedUnitResult> libraryUnits,
) {
  if (!_isPartUnit(unitResult.unit)) return unitResult;
  for (final unit in libraryUnits) {
    if (_hasLibraryDirective(unit.unit)) return unit;
  }
  for (final unit in libraryUnits) {
    if (!_isPartUnit(unit.unit)) return unit;
  }
  return unitResult;
}

bool _isPartUnit(CompilationUnit unit) {
  return unit.directives.any((d) => d is PartOfDirective);
}

bool _hasLibraryDirective(CompilationUnit unit) {
  return unit.directives.any((d) => d is LibraryDirective);
}

String? findProjectRoot(String filePath) {
  var dir = p.dirname(p.absolute(filePath));
  while (true) {
    final lock = p.join(dir, 'pubspec.lock');
    if (File(lock).existsSync()) return dir;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

bool _hasThrowsImport(CompilationUnit unit) {
  for (final directive in unit.directives) {
    if (directive is ImportDirective &&
        directive.uri.stringValue ==
            'package:document_throws_annotation/document_throws_annotation.dart') {
      return true;
    }
  }
  return false;
}

bool _hasProvenanceAnnotations(NodeList<Annotation>? metadata) {
  if (metadata == null || metadata.isEmpty) return false;
  for (final annotation in metadata) {
    if (_annotationName(annotation) != throwingAnnotationName) continue;
    if (_annotationHasProvenance(annotation)) return true;
  }
  return false;
}

bool _hasThrowingAnnotations(NodeList<Annotation>? metadata) {
  return _annotationThrownTypes(metadata).isNotEmpty;
}

bool _hasDocThrowingTags(Comment? comment) {
  return _parseDocThrowingTags(comment).isNotEmpty;
}

bool _annotationHasProvenance(Annotation annotation) {
  final arguments = annotation.arguments?.arguments;
  if (arguments == null) return false;
  for (final argument in arguments) {
    if (argument is! NamedExpression) continue;
    final name = argument.name.label.name;
    if (name == 'call' || name == 'origin') {
      return true;
    }
  }
  return false;
}

class _ImportInsertion {
  final int offset;
  final String text;

  const _ImportInsertion(this.offset, this.text);
}

int _importGroupForUri(String uri) {
  if (uri.startsWith('dart:')) return 0;
  if (uri.startsWith('package:')) return 1;
  return 2;
}

_ImportInsertion _importInsertion(CompilationUnit unit, String content) {
  const newUri =
      'package:document_throws_annotation/document_throws_annotation.dart';
  final newGroup = _importGroupForUri(newUri);
  final imports = <_ImportInfo>[];
  for (final directive in unit.directives) {
    if (directive is ImportDirective) {
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      imports.add(_ImportInfo(directive, uri, _importGroupForUri(uri)));
    }
  }

  if (imports.isNotEmpty) {
    _ImportInfo? previous;
    for (final info in imports) {
      final groupCmp = newGroup.compareTo(info.group);
      if (groupCmp < 0 ||
          (groupCmp == 0 && newUri.compareTo(info.uri) < 0)) {
        final insertAt = (groupCmp < 0 && previous != null)
            ? previous.directive.end
            : info.directive.offset;
        final text = _importText(
          content,
          insertAt,
          nextGroup: info.group,
          nextOffset: info.directive.offset,
          newGroup: newGroup,
        );
        return _ImportInsertion(insertAt, text);
      }
      previous = info;
    }

    final insertAt = imports.last.directive.end;
    final text = _importText(content, insertAt);
    return _ImportInsertion(insertAt, text);
  }

  ImportDirective? lastImport;
  LibraryDirective? library;
  PartDirective? firstPart;
  for (final directive in unit.directives) {
    if (directive is ImportDirective) lastImport = directive;
    if (directive is LibraryDirective && library == null) {
      library = directive;
    }
    if (directive is PartDirective && firstPart == null) {
      firstPart = directive;
    }
  }

  if (lastImport != null) {
    final insertAt = lastImport.end;
    final text = _importText(content, insertAt);
    return _ImportInsertion(insertAt, text);
  }
  if (library != null) {
    final insertAt = library.end;
    final text = _importText(content, insertAt);
    return _ImportInsertion(insertAt, text);
  }
  if (firstPart != null) {
    final insertAt = firstPart.offset;
    final text = _importText(content, insertAt);
    return _ImportInsertion(insertAt, text);
  }
  return _ImportInsertion(0, _importText(content, 0));
}

int _annotationInsertOffset(String content, ExecutableTarget target) {
  if (target.metadata != null && target.metadata!.isNotEmpty) {
    return _lineOffsetAfter(content, target.metadata!.last.end);
  }

  final comment = target.documentationComment;
  if (comment == null) return lineStart(content, target.declarationOffset);

  return _lineOffsetAfter(content, comment.end);
}

enum _DocCommentStyle { none, line, block }

_DocCommentStyle _docCommentStyle(Comment? comment) {
  if (comment == null) return _DocCommentStyle.none;
  final source = comment.toSource();
  if (source.startsWith('///')) return _DocCommentStyle.line;
  if (source.startsWith('/**')) return _DocCommentStyle.block;
  return _DocCommentStyle.line;
}

int _docCommentInsertOffset(
  String content,
  ExecutableTarget target,
  _DocCommentStyle style,
) {
  final comment = target.documentationComment;
  if (comment == null) return lineStart(content, target.declarationOffset);
  if (style == _DocCommentStyle.block) {
    return comment.end - 2;
  }
  return _lineOffsetAfter(content, comment.end);
}

List<SourceEdit> _removeThrowsAnnotations(
  String content,
  NodeList<Annotation>? metadata,
  Set<String> replaceNames,
) {
  if (metadata == null || metadata.isEmpty) return const <SourceEdit>[];
  final edits = <SourceEdit>[];
  for (final annotation in metadata) {
    if (_annotationName(annotation) != throwingAnnotationName) continue;
    final typeName = _annotationTypeName(annotation);
    if (typeName == null || !replaceNames.contains(typeName)) continue;
    final start = lineStart(content, annotation.offset);
    final end = _lineOffsetAfter(content, annotation.end);
    if (end > start) {
      edits.add(SourceEdit(start, end - start, ''));
    }
  }
  return edits;
}

String? _annotationName(Annotation annotation) {
  final name = annotation.name;
  if (name is SimpleIdentifier) return name.name;
  if (name is PrefixedIdentifier) return name.identifier.name;
  return null;
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
    final normalized = _normalizeTypeName(first.toSource());
    if (normalized != null) {
      types.add(normalized);
    }
  }
  return types;
}

String? _annotationTypeName(Annotation annotation) {
  final args = annotation.arguments?.arguments;
  if (args == null || args.isEmpty) return null;
  final first = args.first;
  if (first is ListLiteral) return null;
  return _normalizeTypeName(first.toSource());
}

String? _normalizeTypeName(String rawName) {
  var name = rawName.trim();
  if (name.isEmpty) return null;

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

Map<String, String> _annotationReasonByType(
  NodeList<Annotation>? metadata,
) {
  if (metadata == null || metadata.isEmpty) return const <String, String>{};
  final map = <String, String>{};
  for (final annotation in metadata) {
    if (_annotationName(annotation) != throwingAnnotationName) continue;
    final name = _annotationTypeName(annotation);
    if (name == null) continue;
    final args = annotation.arguments?.arguments;
    if (args == null) continue;
    for (final arg in args) {
      if (arg is! NamedExpression) continue;
      if (arg.name.label.name != 'reason') continue;
      map[name] = arg.expression.toSource();
    }
  }
  return map;
}

List<ThrownTypeInfo> _mergeThrownInfos(List<ThrownTypeInfo> infos) {
  final byName = <String, ThrownTypeInfo>{};
  for (final info in infos) {
    final existing = byName[info.name];
    if (existing == null) {
      byName[info.name] = info;
      continue;
    }
    final mergedType = existing.type ?? info.type;
    final mergedProvenance = <ThrowsProvenance>[
      ...existing.provenance,
    ];
    final seen = <String>{};
    for (final entry in mergedProvenance) {
      seen.add('${entry.call}|${entry.origin ?? ''}');
    }
    for (final entry in info.provenance) {
      final key = '${entry.call}|${entry.origin ?? ''}';
      if (seen.add(key)) {
        mergedProvenance.add(entry);
      }
    }
    byName[info.name] = ThrownTypeInfo(
      info.name,
      mergedType,
      provenance: mergedProvenance,
    );
  }
  return byName.values.toList();
}

String _importText(
  String content,
  int insertAt, {
  int? nextGroup,
  int? nextOffset,
  int? newGroup,
}) {
  final needsLeadingNewline =
      insertAt > 0 && !_isLineBreak(content.codeUnitAt(insertAt - 1));
  final prefix = needsLeadingNewline ? '\n' : '';
  final needsGroupSpacing = nextGroup != null &&
      newGroup != null &&
      nextGroup != newGroup &&
      nextOffset != null &&
      _lineBreakCount(content, insertAt, nextOffset) < 2;
  final suffix = needsGroupSpacing ? '\n' : '';
  return "${prefix}import 'package:document_throws_annotation/document_throws_annotation.dart';\n$suffix";
}

bool _isLineBreak(int codeUnit) => codeUnit == 0x0A || codeUnit == 0x0D;

int _lineOffsetAfter(String content, int offset) {
  var i = offset;
  while (i < content.length && !_isLineBreak(content.codeUnitAt(i))) {
    i++;
  }

  if (i < content.length && content.codeUnitAt(i) == 0x0D) {
    i++;
    if (i < content.length && content.codeUnitAt(i) == 0x0A) {
      i++;
    }
  } else if (i < content.length && content.codeUnitAt(i) == 0x0A) {
    i++;
  }
  return i;
}

int _lineBreakCount(String content, int start, int end) {
  var count = 0;
  var i = start;
  while (i < end) {
    final cu = content.codeUnitAt(i);
    if (cu == 0x0A) {
      count++;
    } else if (cu == 0x0D) {
      count++;
      if (i + 1 < end && content.codeUnitAt(i + 1) == 0x0A) {
        i++;
      }
    }
    i++;
  }
  return count;
}

class _ImportPrefixData {
  final Map<String, String> prefixed;
  final Set<String> unprefixed;
  final Map<String, String> prefixedPackages;
  final Set<String> unprefixedPackages;

  const _ImportPrefixData(
    this.prefixed,
    this.unprefixed,
    this.prefixedPackages,
    this.unprefixedPackages,
  );
}

_ImportPrefixData _collectImportPrefixes(CompilationUnit unit) {
  final prefixed = <String, String>{};
  final unprefixed = <String>{};
  final prefixedPackages = <String, String>{};
  final unprefixedPackages = <String>{};
  for (final directive in unit.directives) {
    if (directive is! ImportDirective) continue;
    final uri = directive.uri.stringValue;
    if (uri == null || uri.isEmpty) continue;
    final prefix = directive.prefix?.name;
    final package = _packageName(uri);
    if (prefix != null && prefix.isNotEmpty) {
      prefixed[uri] = prefix;
      if (package != null && package.isNotEmpty) {
        prefixedPackages.putIfAbsent(package, () => prefix);
      }
    } else {
      unprefixed.add(uri);
      if (package != null && package.isNotEmpty) {
        unprefixedPackages.add(package);
      }
    }
  }
  return _ImportPrefixData(
    prefixed,
    unprefixed,
    prefixedPackages,
    unprefixedPackages,
  );
}

List<String> _formatThrownAnnotations(
  ThrownTypeInfo info,
  _ImportPrefixData importData,
  String libraryUri, {
  required bool includeSource,
  String? reasonSource,
  required CompilationUnit unit,
  required int maxLineLength,
}) {
  final renderedType = _formatThrownType(
    info,
    importData,
    libraryUri,
    unit,
  );
  if (!includeSource || info.provenance.isEmpty) {
    final args = <String>[renderedType];
    if (reasonSource != null) {
      args.add('reason: $reasonSource');
    }
    return _renderThrowingInvocation(args, maxLineLength: maxLineLength);
  }
  final lines = <String>[];
  for (final provenance in info.provenance) {
    final args = <String>[
      renderedType,
      if (reasonSource != null) 'reason: $reasonSource',
      "call: '${_escapeSourceString(_shortenSource(provenance.call))}'",
      if (provenance.origin != null)
        "origin: '${_escapeSourceString(_shortenSource(provenance.origin!))}'",
    ];
    lines.addAll(_renderThrowingInvocation(args, maxLineLength: maxLineLength));
  }
  return lines;
}

String _formatThrownType(
  ThrownTypeInfo info,
  _ImportPrefixData importData,
  String libraryUri,
  CompilationUnit unit,
) {
  var typeUri = _libraryUriForType(info.type);
  typeUri ??= _resolveTypeUriByName(info.name, unit);
  if (typeUri == null || typeUri == libraryUri) {
    return info.name;
  }
  if (importData.unprefixed.contains(typeUri)) {
    return info.name;
  }
  final prefix = importData.prefixed[typeUri];
  if (prefix != null && prefix.isNotEmpty) {
    return '$prefix.${info.name}';
  }
  final typePackage = _packageName(typeUri);
  if (typePackage != null) {
    if (importData.unprefixedPackages.contains(typePackage)) {
      return info.name;
    }
    final packagePrefix = importData.prefixedPackages[typePackage];
    if (packagePrefix != null && packagePrefix.isNotEmpty) {
      return '$packagePrefix.${info.name}';
    }
  }
  return info.name;
}

String? _resolveTypeUriByName(String name, CompilationUnit unit) {
  String? match;
  for (final directive in unit.directives) {
    if (directive is! ImportDirective) continue;
    final libraryImport = directive.libraryImport;
    if (libraryImport == null) continue;
    final library = libraryImport.importedLibrary;
    if (library == null) continue;
    final prefix = directive.prefix?.name;
    final namespace = libraryImport.namespace;
    var element = prefix == null || prefix.isEmpty
        ? namespace.get2(name)
        : namespace.getPrefixed2(prefix, name);
    element ??= _libraryDefinesType(library, name) ? library : null;
    if (element != null) {
      final uri = library.uri.toString();
      if (match != null && match != uri) return null;
      match = uri;
    }
  }
  return match;
}

bool _libraryDefinesType(LibraryElement library, String name) {
  if (library.getClass(name) != null) return true;
  if (library.getEnum(name) != null) return true;
  if (library.getTypeAlias(name) != null) return true;
  if (library.getExtensionType(name) != null) return true;
  if (library.getMixin(name) != null) return true;
  return false;
}

String _escapeSourceString(String value) {
  return value.replaceAll('\\', r'\\').replaceAll("'", r"\'");
}

List<String> _renderThrowingInvocation(
  List<String> args, {
  required int maxLineLength,
}) {
  final singleLine = '@$throwingAnnotationName(${args.join(', ')})';
  if (singleLine.length <= maxLineLength) return [singleLine];
  final lines = <String>['@$throwingAnnotationName('];
  for (final arg in args) {
    lines.add('  $arg,');
  }
  lines.add(')');
  return lines;
}

List<String> _prefixDocCommentLines(
  List<String> lines,
  _DocCommentStyle style,
) {
  final prefix = style == _DocCommentStyle.block ? '* ' : '/// ';
  return [for (final line in lines) '$prefix$line'];
}

String? _renderInsertionText(
  String indent,
  List<String> lines,
  DocumentationStyle documentationStyle,
  _DocCommentStyle commentStyle,
) {
  if (lines.isEmpty) return null;
  final body = lines.join('\n$indent');
  if (documentationStyle == DocumentationStyle.docComment &&
      commentStyle == _DocCommentStyle.block) {
    return '\n$indent$body';
  }
  return '$indent$body\n';
}

bool _hasProvenanceDocTags(Comment? comment) {
  if (comment == null) return false;
  final lines = _docCommentLines(comment);
  final hasThrowing = lines.any(
    (line) => line.trimLeft().startsWith(throwingDocTag),
  );
  if (!hasThrowing) return false;
  final hasProvenance = lines.any(
    (line) => _docThrowingLineKind(line) == _DocThrowingLineKind.provenance,
  );
  if (hasProvenance) return true;
  return _parseDocThrowingTags(comment)
      .any((tag) => tag.hasProvenance);
}

Map<String, String> _docCommentReasonByType(Comment? comment) {
  final tags = _parseDocThrowingTags(comment);
  final result = <String, String>{};
  for (final tag in tags) {
    final reason = tag.reason;
    if (reason == null || reason.isEmpty) continue;
    result[tag.type] = reason;
  }
  return result;
}

List<SourceEdit> _removeDocThrowingTags(
  String content,
  Comment? comment,
) {
  if (comment == null) return const <SourceEdit>[];
  final source = content.substring(comment.offset, comment.end);
  final lines = source.split(RegExp(r'\r?\n'));
  final filtered = _stripDocThrowingLines(lines);
  if (filtered.length == lines.length) return const <SourceEdit>[];
  final replacement = filtered.join('\n');
  return [
    SourceEdit(comment.offset, comment.end - comment.offset, replacement),
  ];
}

String _replaceDocThrowingTags(
  String content,
  Comment comment,
  List<String> newLines,
  String indent,
  _DocCommentStyle style,
) {
  final existingLines = _docCommentLines(comment);
  final kept = _stripDocThrowingLines(existingLines);
  final merged = [...kept, ...newLines];
  var updated = _buildDocComment(merged, indent, style);
  if (updated.endsWith('\n') &&
      comment.end < content.length &&
      content.substring(comment.end).startsWith('\n')) {
    updated = updated.substring(0, updated.length - 1);
  }
  if (updated.endsWith('\n') &&
      comment.end + 1 < content.length &&
      content.substring(comment.end).startsWith('\r\n')) {
    updated = updated.substring(0, updated.length - 1);
  }
  return updated;
}

List<String> _docCommentLines(Comment comment) {
  final source = comment.tokens.map((token) => token.lexeme).join('\n');
  final trimmedLeft = source.trimLeft();
  if (trimmedLeft.startsWith('///')) {
    final lines = source.split(RegExp(r'\r?\n'));
    return [
      for (final line in lines)
        _stripDocLinePrefix(line, '///'),
    ];
  }
  if (trimmedLeft.startsWith('/**')) {
    final trimmed = source
        .replaceFirst('/**', '')
        .replaceFirst('*/', '')
        .trim();
    final lines = trimmed.split(RegExp(r'\r?\n'));
    return [for (final line in lines) _stripBlockDocLine(line)];
  }
  return [source.trim()];
}

String _buildDocComment(
  List<String> lines,
  String indent,
  _DocCommentStyle style,
) {
  final trimmed = List<String>.from(lines);
  while (trimmed.isNotEmpty && trimmed.last.trim().isEmpty) {
    trimmed.removeLast();
  }
  if (style == _DocCommentStyle.block) {
    final body = trimmed.map((line) => '$indent * $line').join('\n');
    return '$indent/**\n$body\n$indent */';
  }
  final body = trimmed
      .map(
        (line) =>
            line.isEmpty
                ? '$indent///'
                : line.startsWith(' ')
                ? '$indent///$line'
                : '$indent/// $line',
      )
      .join('\n');
  return '$body\n';
}

String _stripDocLinePrefix(String line, String prefix) {
  final index = line.indexOf(prefix);
  if (index == -1) return line.trim();
  final content = line.substring(index + prefix.length);
  if (content.trim().isEmpty) return '';
  return content;
}

String _stripBlockDocLine(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('*')) {
    return trimmed.substring(1).trimLeft();
  }
  return trimmed.trimRight();
}

class _DocThrowingTag {
  final String type;
  final String? reason;
  final bool hasProvenance;

  const _DocThrowingTag(
    this.type, {
    this.reason,
    required this.hasProvenance,
  });
}

List<_DocThrowingTag> _parseDocThrowingTags(Comment? comment) {
  if (comment == null) return const <_DocThrowingTag>[];
  final text = _docCommentLines(comment).join('\n');
  return _extractDocThrowingTags(text);
}

enum _DocThrowingLineKind { throwingTag, provenance, close, type, other }

String _docLineContentForDetection(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('///')) {
    return _stripDocLinePrefix(line, '///');
  }
  if (trimmed.startsWith('/**')) {
    return trimmed.substring(3).trimLeft();
  }
  if (trimmed.startsWith('*/')) return '';
  if (trimmed.startsWith('*')) return _stripBlockDocLine(line);
  return line;
}

_DocThrowingLineKind _docThrowingLineKind(String line) {
  final trimmed = _docLineContentForDetection(line).trimLeft();
  if (trimmed.startsWith(throwingDocTag)) return _DocThrowingLineKind.throwingTag;
  if (trimmed.startsWith('call:') || trimmed.startsWith('origin:')) {
    return _DocThrowingLineKind.provenance;
  }
  if (trimmed == ')') return _DocThrowingLineKind.close;
  if (trimmed.endsWith(',')) return _DocThrowingLineKind.type;
  return _DocThrowingLineKind.other;
}

List<String> _stripDocThrowingLines(List<String> lines) {
  if (lines.isEmpty) return lines;
  final result = <String>[];
  var inThrowingBlock = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final kind = _docThrowingLineKind(line);
    if (kind == _DocThrowingLineKind.throwingTag) {
      final content = _docLineContentForDetection(line);
      final open = content.indexOf('(');
      if (open == -1 || content.indexOf(')', open + 1) == -1) {
        inThrowingBlock = true;
      }
      continue;
    }
    if (inThrowingBlock) {
      if (kind == _DocThrowingLineKind.close) {
        inThrowingBlock = false;
      }
      continue;
    }
    if (kind == _DocThrowingLineKind.provenance) {
      continue;
    }
    if (kind == _DocThrowingLineKind.type &&
        _hasProvenanceOrCloseAhead(lines, i)) {
      continue;
    }
    if (kind == _DocThrowingLineKind.close) {
      final prevKind =
          i > 0 ? _docThrowingLineKind(lines[i - 1]) : _DocThrowingLineKind.other;
      if (prevKind == _DocThrowingLineKind.provenance ||
          prevKind == _DocThrowingLineKind.type) {
        continue;
      }
    }
    result.add(line);
  }
  return result;
}

bool _hasProvenanceOrCloseAhead(List<String> lines, int start) {
  for (var i = start + 1; i < lines.length; i++) {
    final kind = _docThrowingLineKind(lines[i]);
    if (kind == _DocThrowingLineKind.provenance ||
        kind == _DocThrowingLineKind.close) {
      return true;
    }
    if (kind != _DocThrowingLineKind.type) return false;
  }
  return false;
}

List<_DocThrowingTag> _extractDocThrowingTags(String text) {
  final tags = <_DocThrowingTag>[];
  var index = 0;
  while (true) {
    final tagIndex = text.indexOf(throwingDocTag, index);
    if (tagIndex == -1) break;
    final openIndex = text.indexOf('(', tagIndex + throwingDocTag.length);
    if (openIndex == -1) break;
    final closeIndex = _findMatchingParen(text, openIndex);
    if (closeIndex == -1) break;
    final args = text.substring(openIndex + 1, closeIndex);
    final parts = _splitDocArgs(args);
    if (parts.isEmpty) {
      index = closeIndex + 1;
      continue;
    }
    var typeName = parts.first.trim();
    if (typeName.startsWith('const ')) {
      typeName = typeName.substring(6).trimLeft();
    }
    final normalized = _normalizeTypeName(typeName);
    if (normalized != null) {
      final reason = _namedDocArg(parts, 'reason');
      final hasProv =
          _namedDocArg(parts, 'call') != null ||
          _namedDocArg(parts, 'origin') != null;
      tags.add(
        _DocThrowingTag(
          normalized,
          reason: reason,
          hasProvenance: hasProv,
        ),
      );
    }
    index = closeIndex + 1;
  }
  return tags;
}

List<String> _splitDocArgs(String args) {
  final parts = <String>[];
  var depthParen = 0;
  var depthAngle = 0;
  var inSingle = false;
  var inDouble = false;
  var escape = false;
  var start = 0;
  for (var i = 0; i < args.length; i++) {
    final ch = args[i];
    if (inSingle) {
      if (escape) {
        escape = false;
      } else if (ch == '\\') {
        escape = true;
      } else if (ch == "'") {
        inSingle = false;
      }
      continue;
    }
    if (inDouble) {
      if (escape) {
        escape = false;
      } else if (ch == '\\') {
        escape = true;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }
    if (ch == "'") {
      inSingle = true;
      continue;
    }
    if (ch == '"') {
      inDouble = true;
      continue;
    }
    if (ch == '(') {
      depthParen++;
      continue;
    }
    if (ch == ')' && depthParen > 0) {
      depthParen--;
      continue;
    }
    if (ch == '<') {
      depthAngle++;
      continue;
    }
    if (ch == '>' && depthAngle > 0) {
      depthAngle--;
      continue;
    }
    if (ch == ',' && depthParen == 0 && depthAngle == 0) {
      parts.add(args.substring(start, i).trim());
      start = i + 1;
    }
  }
  final tail = args.substring(start).trim();
  if (tail.isNotEmpty) parts.add(tail);
  return parts;
}

String? _namedDocArg(List<String> args, String name) {
  final prefix = '$name:';
  for (final part in args.skip(1)) {
    final trimmed = part.trimLeft();
    if (!trimmed.startsWith(prefix)) continue;
    return trimmed.substring(prefix.length).trimLeft();
  }
  return null;
}

int _findMatchingParen(String text, int openIndex) {
  var depth = 0;
  var inSingle = false;
  var inDouble = false;
  var escape = false;
  for (var i = openIndex + 1; i < text.length; i++) {
    final ch = text[i];
    if (inSingle) {
      if (escape) {
        escape = false;
      } else if (ch == '\\') {
        escape = true;
      } else if (ch == "'") {
        inSingle = false;
      }
      continue;
    }
    if (inDouble) {
      if (escape) {
        escape = false;
      } else if (ch == '\\') {
        escape = true;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }
    if (ch == "'") {
      inSingle = true;
      continue;
    }
    if (ch == '"') {
      inDouble = true;
      continue;
    }
    if (ch == '(') {
      depth++;
      continue;
    }
    if (ch == ')') {
      if (depth == 0) return i;
      depth--;
    }
  }
  return -1;
}

String _shortenSource(String source) {
  final parts = source.split('|');
  if (parts.isEmpty) return source;
  final uri = _shortenSourceUri(parts.first);
  final namePart = parts.length > 1 ? parts[1] : '';
  var shortened = _shortenMethodName(namePart);
  if (shortened.isEmpty) shortened = namePart;
  return '$uri|$shortened';
}

String _shortenSourceUri(String uriValue) {
  Uri? uri;
  try {
    uri = Uri.parse(uriValue);
  } on FormatException {
    return uriValue;
  }
  final scheme = uri.scheme;
  if (scheme == 'dart') return uriValue;
  if (scheme == 'package') {
    return _packageName(uriValue) ?? uriValue;
  }
  if (scheme != 'file') return uriValue;

  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  final items = segments.toList();
  if (items.isEmpty) return uriValue;

  final dartIndex = items.indexOf('dart-sdk');
  if (dartIndex != -1) {
    final libIndex = items.indexOf('lib');
    if (libIndex != -1 && libIndex + 1 < items.length) {
      return 'dart:${items[libIndex + 1]}';
    }
  }

  final libIndex = items.indexOf('lib');
  if (libIndex > 0) {
    return _stripVersionSuffix(items[libIndex - 1]);
  }

  final cachePackage = _packageFromCacheSegments(items);
  if (cachePackage != null) return cachePackage;

  return _stripVersionSuffix(items.last);
}

String? _packageFromCacheSegments(List<String> items) {
  final hostedIndex = items.indexOf('hosted');
  if (hostedIndex != -1 && hostedIndex + 2 < items.length) {
    return _stripVersionSuffix(items[hostedIndex + 2]);
  }
  final gitIndex = items.indexOf('git');
  if (gitIndex != -1 && gitIndex + 1 < items.length) {
    return _stripVersionSuffix(items[gitIndex + 1]);
  }
  final pathIndex = items.indexOf('path');
  if (pathIndex != -1 && pathIndex + 1 < items.length) {
    return _stripVersionSuffix(items[pathIndex + 1]);
  }
  return null;
}

String _shortenMethodName(String namePart) {
  var name = namePart;
  final hashIndex = name.lastIndexOf('#');
  if (hashIndex != -1) {
    name = name.substring(hashIndex + 1);
  }
  final parenIndex = name.indexOf('(');
  if (parenIndex != -1) {
    name = name.substring(0, parenIndex);
  }
  return name;
}

String _stripVersionSuffix(String name) {
  final dashIndex = name.lastIndexOf('-');
  if (dashIndex <= 0 || dashIndex == name.length - 1) return name;
  final suffix = name.substring(dashIndex + 1);
  if (_looksLikeVersion(suffix) || _looksLikeGitHash(suffix)) {
    return name.substring(0, dashIndex);
  }
  return name;
}

bool _looksLikeVersion(String value) {
  if (value.isEmpty) return false;
  if (!_isDigit(value.codeUnitAt(0))) return false;
  var hasDigit = false;
  for (final unit in value.codeUnits) {
    if (_isDigit(unit)) {
      hasDigit = true;
      continue;
    }
    if (_isLetter(unit) || unit == 0x2E || unit == 0x2B || unit == 0x2D) {
      continue;
    }
    return false;
  }
  return hasDigit;
}

bool _looksLikeGitHash(String value) {
  if (value.length < 7) return false;
  for (final unit in value.codeUnits) {
    final isDigit = _isDigit(unit);
    final isHexLower = unit >= 0x61 && unit <= 0x66;
    final isHexUpper = unit >= 0x41 && unit <= 0x46;
    if (!(isDigit || isHexLower || isHexUpper)) return false;
  }
  return true;
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

bool _isLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

String? _libraryUriForType(DartType? type) {
  if (type is InterfaceType) {
    final uri = type.element.library.firstFragment.source.uri;
    return uri.toString();
  }
  return null;
}

String? _packageName(String uri) {
  if (!uri.startsWith('package:')) return null;
  final trimmed = uri.substring('package:'.length);
  final slash = trimmed.indexOf('/');
  if (slash == -1) return trimmed;
  return trimmed.substring(0, slash);
}

class _ImportInfo {
  final ImportDirective directive;
  final String uri;
  final int group;

  const _ImportInfo(this.directive, this.uri, this.group);
}

Map<String, CompilationUnit> unitsByPathFromResolvedUnits(
  Iterable<ResolvedUnitResult> units,
) {
  final map = <String, CompilationUnit>{};
  for (final unit in units) {
    map[unit.path] = unit.unit;
  }
  return map;
}

class _ExecutableCollector extends RecursiveAstVisitor<void> {
  final List<ExecutableTarget> targets = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    targets.add(
      ExecutableTarget(
        body: node.body,
        metadata: node.metadata,
        declarationOffset: node.offset,
        documentationComment: node.documentationComment,
      ),
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    targets.add(
      ExecutableTarget(
        body: node.body,
        metadata: node.metadata,
        declarationOffset: node.offset,
        documentationComment: node.documentationComment,
      ),
    );
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      targets.add(
        ExecutableTarget(
          body: node.functionExpression.body,
          metadata: node.metadata,
          declarationOffset: node.offset,
          documentationComment: node.documentationComment,
        ),
      );
    }
    super.visitFunctionDeclaration(node);
  }
}
