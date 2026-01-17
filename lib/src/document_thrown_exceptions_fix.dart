import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'document_thrown_exceptions.dart';
import 'document_thrown_exceptions_fix_utils.dart';
import 'throws_cache_lookup.dart';

class DocumentThrownExceptionsFix extends ResolvedCorrectionProducer {
  static const FixKind _fixKind = FixKind(
    'lint_hard.fix.document_thrown_exceptions',
    DartFixKindPriority.standard,
    'Document thrown exceptions',
  );

  // Wire the fix into the analysis server context.
  DocumentThrownExceptionsFix({required super.context});

  @override
  // Apply within a single file without needing broader analysis.
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossSingleFile;

  @override
  // Expose the fix kind identifier for this lint.
  FixKind get fixKind => _fixKind;

  @override
  // Insert missing @Throws annotations for the reported executable.
  Future<void> compute(ChangeBuilder builder) async {
    if (diagnostic?.diagnosticCode != DocumentThrownExceptions.code) return;

    final target = findExecutableTarget(node);
    if (target == null) return;

    final missing = missingThrownTypeDocs(
      target.body,
      target.metadata,
      unitsByPath: unitsByPathFromResolvedUnits(libraryResult.units),
      externalLookup: _externalLookupForPath(file),
    );
    if (missing.isEmpty) return;

    final content = unitResult.content;
    final insertOffset = _annotationInsertOffset(content, target);
    final indent = indentAtOffset(content, target.declarationOffset);

    final lines = [
      for (final type in missing.toList()..sort()) '@Throws($type)',
    ];

    await builder.addDartFileEdit(file, (builder) {
      if (!_hasThrowsImport(unitResult.unit)) {
        final insertion = _importInsertion(unitResult.unit, content);
        builder.addSimpleInsertion(insertion.offset, insertion.text);
      }
      builder.addSimpleInsertion(
        insertOffset,
        '$indent${lines.join("\n$indent")}\n',
      );
    });
  }
}

bool _hasThrowsImport(CompilationUnit unit) {
  for (final directive in unit.directives) {
    if (directive is ImportDirective &&
        directive.uri.stringValue == 'package:lint_hard/throws.dart') {
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
  const newUri = 'package:lint_hard/throws.dart';
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
  return "${prefix}import 'package:lint_hard/throws.dart';\n$suffix";
}

bool _isLineBreak(int codeUnit) => codeUnit == 0x0A || codeUnit == 0x0D;

int _annotationInsertOffset(String content, ExecutableTarget target) {
  if (target.metadata != null && target.metadata!.isNotEmpty) {
    return _lineOffsetAfter(content, target.metadata!.last.end);
  }

  final comment = target.documentationComment;
  if (comment == null) return lineStart(content, target.declarationOffset);

  return _lineOffsetAfter(content, comment.end);
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

class _ImportInfo {
  final ImportDirective directive;
  final String uri;
  final int group;

  const _ImportInfo(this.directive, this.uri, this.group);
}

ThrowsCacheLookup? _externalLookupForPath(String filePath) {
  final root = findProjectRoot(filePath);
  if (root == null) return null;
  return ThrowsCacheLookup.forProjectRoot(root);
}
