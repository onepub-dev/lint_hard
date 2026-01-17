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
    final declLineStart = lineStart(content, target.declarationOffset);
    final indent = indentAtOffset(content, target.declarationOffset);

    final types = (missing.toList()..sort()).join(', ');

    await builder.addDartFileEdit(file, (builder) {
      if (!_hasThrowsImport(unitResult.unit)) {
        final insertAt = _importInsertOffset(unitResult.unit, content);
        builder.addSimpleInsertion(
          insertAt,
          "import 'package:lint_hard/throws.dart';\n",
        );
      }
      final throwsAnnotation = _findThrowsAnnotation(target.metadata);
      if (throwsAnnotation != null) {
        final listLiteral = _throwsListLiteral(throwsAnnotation);
        if (listLiteral != null) {
          final insertOffset = listLiteral.rightBracket.offset;
          final prefix = listLiteral.elements.isEmpty ? '' : ', ';
          builder.addSimpleInsertion(insertOffset, '$prefix$types');
        } else {
          builder.addSimpleInsertion(
            declLineStart,
            '$indent@Throws([$types])\n',
          );
        }
      } else {
        builder.addSimpleInsertion(
          declLineStart,
          '$indent@Throws([$types])\n',
        );
      }
    });
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

ThrowsCacheLookup? _externalLookupForPath(String filePath) {
  final root = findProjectRoot(filePath);
  if (root == null) return null;
  return ThrowsCacheLookup.forProjectRoot(root);
}
