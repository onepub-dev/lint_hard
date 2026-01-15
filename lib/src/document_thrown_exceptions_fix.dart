import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'document_thrown_exceptions.dart';

class DocumentThrownExceptionsFix extends ResolvedCorrectionProducer {
  static const FixKind _fixKind = FixKind(
    'lint_hard.fix.document_thrown_exceptions',
    DartFixKindPriority.standard,
    'Document thrown exceptions',
  );

  DocumentThrownExceptionsFix({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossSingleFile;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (diagnostic?.diagnosticCode != DocumentThrownExceptions.code) return;

    final target = _findTarget(node);
    if (target == null) return;

    final missing =
        missingThrownTypeDocs(target.body, target.documentationComment);
    if (missing.isEmpty) return;

    final content = unitResult.content;
    final declLineStart = _lineStart(content, target.declarationOffset);
    final indent = _indentAtOffset(content, target.declarationOffset);

    final lines = (missing.toList()..sort())
        .map((type) => '$indent/// Throws [$type].')
        .join('\n');

    await builder.addDartFileEdit(file, (builder) {
      if (target.documentationComment != null) {
        builder.addSimpleInsertion(target.documentationComment!.end, '\n$lines');
      } else {
        builder.addSimpleInsertion(declLineStart, '$lines\n');
      }
    });
  }
}

_ExecutableTarget? _findTarget(AstNode node) {
  final method = node.thisOrAncestorOfType<MethodDeclaration>();
  if (method != null) {
    return _ExecutableTarget(
      body: method.body,
      documentationComment: method.documentationComment,
      declarationOffset: method.offset,
    );
  }

  final ctor = node.thisOrAncestorOfType<ConstructorDeclaration>();
  if (ctor != null) {
    return _ExecutableTarget(
      body: ctor.body,
      documentationComment: ctor.documentationComment,
      declarationOffset: ctor.offset,
    );
  }

  final function = node.thisOrAncestorOfType<FunctionDeclaration>();
  if (function != null && function.parent is CompilationUnit) {
    return _ExecutableTarget(
      body: function.functionExpression.body,
      documentationComment: function.documentationComment,
      declarationOffset: function.offset,
    );
  }

  return null;
}

int _lineStart(String content, int offset) {
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

String _indentAtOffset(String content, int offset) {
  final start = _lineStart(content, offset);
  var i = start;
  while (i < offset) {
    final ch = content.codeUnitAt(i);
    if (ch != 0x20 && ch != 0x09) break; // space or tab
    i++;
  }
  return content.substring(start, i);
}

class _ExecutableTarget {
  final FunctionBody body;
  final Comment? documentationComment;
  final int declarationOffset;

  _ExecutableTarget({
    required this.body,
    required this.documentationComment,
    required this.declarationOffset,
  });
}
