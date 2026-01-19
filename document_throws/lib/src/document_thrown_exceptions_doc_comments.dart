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
    final mentioned = <String>{};
    mentioned.addAll(inlineMentionedTypes(comment));
    mentioned.addAll(thrownTypes(comment));
    return mentioned;
  }

  Set<String> inlineMentionedTypes(Comment? comment) {
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
    return mentioned;
  }

  bool _referenceHasThrowCue(Comment comment, CommentReference reference) {
    final raw = reference.toSource();
    final bracketed = '[$raw]';
    for (final line in _commentLines(comment)) {
      if (!(line.contains(raw) || line.contains(bracketed))) continue;
      if (_containsThrowWord(line)) return true;
    }
    return false;
  }

  List<String> _commentLines(Comment comment) {
    final source = comment.tokens.map((token) => token.lexeme).join('\n');
    final lines = source.split('\n');
    return [
      for (final line in lines)
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
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
