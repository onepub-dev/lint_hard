import 'package:analyzer/dart/ast/ast.dart';

import 'document_thrown_exceptions_type_names.dart';
import 'throwing_doc_parser.dart';

class DocCommentAnalyzer {
  Set<String> thrownTypes(Comment? comment) {
    final parsed = parseThrowingDocComment(comment);
    if (parsed.typeNames.isEmpty) return const <String>{};
    final types = <String>{};
    for (final rawType in parsed.typeNames) {
      final normalized = typeNameNormalizer.normalizeTypeName(rawType);
      if (normalized != null) {
        types.add(normalized);
      }
    }
    return types;
  }

  Set<String> mentionedTypes(Comment? comment) {
    if (comment == null) return const <String>{};
    final mentioned = <String>{};
    for (final reference in comment.references) {
      if (!_referenceHasThrowCue(comment, reference)) continue;
      final name = _commentReferenceName(reference);
      if (name == null) continue;
      final normalized = typeNameNormalizer.normalizeTypeName(name);
      if (normalized != null) {
        mentioned.add(normalized);
      }
    }
    mentioned.addAll(thrownTypes(comment));
    return mentioned;
  }

  bool _referenceHasThrowCue(Comment comment, CommentReference reference) {
    final text = _docCommentText(comment);
    if (!_containsThrowWord(text)) return false;
    final raw = reference.toSource();
    final bracketed = '[$raw]';
    return text.contains(raw) || text.contains(bracketed);
  }

  String _docCommentText(Comment comment) {
    final source = comment.tokens.map((token) => token.lexeme).join('\n');
    final trimmedLeft = source.trimLeft();
    if (trimmedLeft.startsWith('///')) {
      final lines = source.split('\n');
      return lines.map(_stripDocLinePrefix).join('\n').trim();
    }
    if (trimmedLeft.startsWith('/**')) {
      var trimmed = source;
      trimmed = _stripLeadingBlockPrefix(trimmed);
      trimmed = _stripTrailingBlockSuffix(trimmed);
      final lines = trimmed.split('\n');
      return lines.map(_stripBlockDocLine).join('\n').trim();
    }
    return source.trim();
  }

  String _stripDocLinePrefix(String line) {
    final index = line.indexOf('///');
    if (index == -1) return line.trim();
    return line.substring(index + 3).trimLeft();
  }

  String _stripBlockDocLine(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('*')) {
      return trimmed.substring(1).trimLeft();
    }
    return trimmed.trimRight();
  }

  String _stripLeadingBlockPrefix(String text) {
    final index = text.indexOf('/**');
    if (index == -1) return text;
    return text.substring(index + 3);
  }

  String _stripTrailingBlockSuffix(String text) {
    final index = text.lastIndexOf('*/');
    if (index == -1) return text;
    return text.substring(0, index);
  }

  bool _containsThrowWord(String sentence) {
    final lower = sentence.toLowerCase();
    for (var i = 0; i < lower.length; i++) {
      if (!_isLetter(lower.codeUnitAt(i))) continue;
      if (!_startsWith(lower, i, 'throw')) continue;
      final before = i == 0 ? null : lower.codeUnitAt(i - 1);
      if (before != null && _isLetter(before)) continue;
      final afterIndex = i + 5;
      if (afterIndex < lower.length && _isLetter(lower.codeUnitAt(afterIndex))) {
        return true;
      }
      return true;
    }
    return false;
  }

  bool _startsWith(String text, int index, String value) {
    if (index + value.length > text.length) return false;
    for (var i = 0; i < value.length; i++) {
      if (text.codeUnitAt(index + i) != value.codeUnitAt(i)) return false;
    }
    return true;
  }

  bool _isLetter(int codeUnit) {
    return (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122);
  }

  String? _commentReferenceName(CommentReference reference) {
    final expression = reference.expression;
    if (expression is SimpleIdentifier) {
      return expression.name;
    }
    if (expression is PrefixedIdentifier) {
      return expression.identifier.name;
    }
    if (expression is PropertyAccess) {
      return expression.propertyName.name;
    }
    if (expression is TypeLiteral) {
      return expression.type.toSource();
    }
    if (expression is ConstructorReference) {
      return expression.constructorName.type.name.lexeme;
    }
    return expression.toSource();
  }
}
