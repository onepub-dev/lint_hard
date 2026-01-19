import 'package:analyzer/dart/ast/ast.dart';

class TypeNameNormalizer {
  const TypeNameNormalizer();

  String? normalizeTypeName(String rawName) {
    var name = rawName.trim();
    if (name.isEmpty) return null;

    final genericSplit = name.split('<');
    name = genericSplit.first;

    final dotIndex = name.lastIndexOf('.');
    if (dotIndex != -1) {
      name = name.substring(dotIndex + 1);
    }

    if (name == 'dynamic' || name == 'Object' || name == 'Never') return null;
    return name;
  }

  String? normalizeCatchTypeName(String rawName) {
    var name = rawName.trim();
    if (name.isEmpty) return null;

    name = name.split(RegExp(r'\s+')).first;

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

  String? catchTypeName(TypeAnnotation exceptionType) {
    if (exceptionType is NamedType) {
      return normalizeCatchTypeName(exceptionType.name.lexeme);
    }
    return normalizeCatchTypeName(exceptionType.toSource());
  }
}

const typeNameNormalizer = TypeNameNormalizer();
