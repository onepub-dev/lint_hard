import 'package:analyzer/dart/ast/ast.dart';

import 'throwing_annotation.dart';

class ThrowingDocParseError {
  final String message;

  const ThrowingDocParseError(this.message);
}

class ThrowingDocParseResult {
  final List<String> typeNames;
  final List<ThrowingDocParseError> errors;

  const ThrowingDocParseResult({
    required this.typeNames,
    required this.errors,
  });
}

ThrowingDocParseResult parseThrowingDocComment(Comment? comment) {
  if (comment == null) {
    return const ThrowingDocParseResult(typeNames: [], errors: []);
  }
  final text = _docCommentText(comment);
  if (text.isEmpty) {
    return const ThrowingDocParseResult(typeNames: [], errors: []);
  }
  return parseThrowingDocText(text);
}

ThrowingDocParseResult parseThrowingDocText(String text) {
  final types = <String>[];
  final errors = <ThrowingDocParseError>[];
  var index = 0;
  while (true) {
    final tagIndex = text.indexOf(throwingDocTag, index);
    if (tagIndex == -1) break;
    final openIndex = text.indexOf('(', tagIndex + throwingDocTag.length);
    if (openIndex == -1) {
      errors.add(const ThrowingDocParseError('Missing "(" after @Throwing.'));
      index = tagIndex + throwingDocTag.length;
      continue;
    }
    final closeIndex = _findMatchingParen(text, openIndex);
    if (closeIndex == -1) {
      errors.add(const ThrowingDocParseError('Missing ")" in @Throwing call.'));
      break;
    }
    final args = text.substring(openIndex + 1, closeIndex);
    final firstArg = _firstDocArgument(args);
    if (firstArg == null) {
      errors.add(
        const ThrowingDocParseError(
          'Missing exception type in @Throwing call.',
        ),
      );
    } else {
      var candidate = firstArg.trim();
      if (candidate.startsWith('const ')) {
        candidate = candidate.substring(6).trimLeft();
      }
      types.add(candidate);
    }
    index = closeIndex + 1;
  }
  return ThrowingDocParseResult(typeNames: types, errors: errors);
}

String _docCommentText(Comment comment) {
  final source = comment.tokens.map((token) => token.lexeme).join('\n');
  final trimmedLeft = source.trimLeft();
  if (trimmedLeft.startsWith('///')) {
    final lines = source.split(RegExp(r'\r?\n'));
    return lines
        .map((line) => _stripDocLinePrefix(line, '///'))
        .join('\n')
        .trim();
  }
  if (trimmedLeft.startsWith('/**')) {
    final trimmed = source
        .replaceFirst('/**', '')
        .replaceFirst('*/', '')
        .trim();
    final lines = trimmed.split(RegExp(r'\r?\n'));
    return lines.map(_stripBlockDocLine).join('\n').trim();
  }
  return source.trim();
}

String _stripDocLinePrefix(String line, String prefix) {
  final index = line.indexOf(prefix);
  if (index == -1) return line.trim();
  return line.substring(index + prefix.length).trimLeft();
}

String _stripBlockDocLine(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('*')) {
    return trimmed.substring(1).trimLeft();
  }
  return trimmed.trimRight();
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

String? _firstDocArgument(String args) {
  var depthParen = 0;
  var depthAngle = 0;
  var inSingle = false;
  var inDouble = false;
  var escape = false;
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
      final value = args.substring(0, i).trim();
      return value.isEmpty ? null : value;
    }
  }
  final value = args.trim();
  return value.isEmpty ? null : value;
}
