import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

String? constructorEnclosingTypeName(ConstructorDeclaration node) {
  final parent = node.parent;
  if (parent is ClassDeclaration) {
    return parent.namePart.typeName.lexeme;
  }
  if (parent is EnumDeclaration) {
    return parent.namePart.typeName.lexeme;
  }
  if (parent is ExtensionTypeDeclaration) {
    return parent.namePart.typeName.lexeme;
  }
  return node.typeName?.name;
}

Token constructorReportToken(ConstructorDeclaration node) {
  return node.typeName?.beginToken ??
      node.name ??
      node.firstTokenAfterCommentAndMetadata;
}
