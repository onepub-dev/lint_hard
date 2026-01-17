import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:path/path.dart' as p;

import 'document_thrown_exceptions.dart';
import 'throws_cache_lookup.dart';

List<SourceEdit> documentThrownExceptionEdits(
  ResolvedUnitResult unitResult,
  Iterable<ResolvedUnitResult> libraryUnits, {
  ThrowsCacheLookup? externalLookup,
}) {
  final unitsByPath = unitsByPathFromResolvedUnits(libraryUnits);
  final collector = _ExecutableCollector();
  unitResult.unit.accept(collector);

  final content = unitResult.content;
  final edits = <SourceEdit>[];
  var hasImport = _hasThrowsImport(unitResult.unit);
  for (final target in collector.targets) {
    final missing = missingThrownTypeDocs(
      target.body,
      target.metadata,
      unitsByPath: unitsByPath,
      externalLookup: externalLookup,
    );
    if (missing.isEmpty) continue;

    final insertOffset = _annotationInsertOffset(content, target);
    final indent = indentAtOffset(content, insertOffset);
    final types = (missing.toList()..sort()).join(', ');

    final throwsAnnotation = _findThrowsAnnotation(target.metadata);
    if (throwsAnnotation != null) {
      final listLiteral = _throwsListLiteral(throwsAnnotation);
      if (listLiteral != null) {
        final insertOffset = listLiteral.rightBracket.offset;
        final prefix = listLiteral.elements.isEmpty ? '' : ', ';
        edits.add(
          SourceEdit(insertOffset, 0, '$prefix$types'),
        );
      } else {
        edits.add(
          SourceEdit(insertOffset, 0, '$indent@Throws([$types])\n'),
        );
      }
    } else {
      edits.add(
        SourceEdit(insertOffset, 0, '$indent@Throws([$types])\n'),
      );
    }
    if (!hasImport) {
      final insertion = _importInsertion(unitResult.unit, content);
      edits.add(SourceEdit(insertion.offset, 0, insertion.text));
      hasImport = true;
    }
  }

  return edits;
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

Annotation? _findThrowsAnnotation(NodeList<Annotation>? metadata) {
  if (metadata == null || metadata.isEmpty) return null;
  for (final annotation in metadata) {
    if (_annotationName(annotation) == 'Throws') return annotation;
  }
  return null;
}

String? _annotationName(Annotation annotation) {
  final name = annotation.name;
  if (name is SimpleIdentifier) return name.name;
  if (name is PrefixedIdentifier) return name.identifier.name;
  return null;
}

ListLiteral? _throwsListLiteral(Annotation annotation) {
  final args = annotation.arguments?.arguments;
  if (args == null || args.isEmpty) return null;
  final first = args.first;
  if (first is ListLiteral) return first;
  return null;
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

int _annotationInsertOffset(String content, ExecutableTarget target) {
  final comment = target.documentationComment;
  if (comment == null) return lineStart(content, target.declarationOffset);

  var i = comment.end;
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
