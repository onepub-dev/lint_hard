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

    final declLineStart = lineStart(content, target.declarationOffset);
    final indent = indentAtOffset(content, target.declarationOffset);
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
          SourceEdit(declLineStart, 0, '$indent@Throws([$types])\n'),
        );
      }
    } else {
      edits.add(SourceEdit(declLineStart, 0, '$indent@Throws([$types])\n'));
    }
    if (!hasImport) {
      final insertAt = _importInsertOffset(unitResult.unit, content);
      edits.add(
        SourceEdit(insertAt, 0, "import 'package:lint_hard/throws.dart';\n"),
      );
      hasImport = true;
    }
  }

  edits.sort((a, b) => a.offset.compareTo(b.offset));
  return edits;
}

ExecutableTarget? findExecutableTarget(AstNode node) {
  final method = node.thisOrAncestorOfType<MethodDeclaration>();
  if (method != null) {
    return ExecutableTarget(
      body: method.body,
      metadata: method.metadata,
      declarationOffset: method.offset,
    );
  }

  final ctor = node.thisOrAncestorOfType<ConstructorDeclaration>();
  if (ctor != null) {
    return ExecutableTarget(
      body: ctor.body,
      metadata: ctor.metadata,
      declarationOffset: ctor.offset,
    );
  }

  final function = node.thisOrAncestorOfType<FunctionDeclaration>();
  if (function != null && function.parent is CompilationUnit) {
    return ExecutableTarget(
      body: function.functionExpression.body,
      metadata: function.metadata,
      declarationOffset: function.offset,
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

  ExecutableTarget({
    required this.body,
    required this.metadata,
    required this.declarationOffset,
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

int _importInsertOffset(CompilationUnit unit, String content) {
  if (unit.directives.isEmpty) return 0;
  final last = unit.directives.last;
  final end = last.end;
  final needsNewline = end < content.length && content.codeUnitAt(end) != 0x0A;
  return needsNewline ? end + 1 : end;
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
        ),
      );
    }
    super.visitFunctionDeclaration(node);
  }
}
