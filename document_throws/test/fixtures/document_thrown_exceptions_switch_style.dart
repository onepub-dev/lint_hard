import 'package:document_throws_annotation/document_throws_annotation.dart';

class BadStateException implements Exception {}
class MissingFileException implements Exception {}

@Throwing(BadStateException)
void annotatedMethod() {
  throw BadStateException();
}

/// @Throwing(MissingFileException)
void documentedMethod() {
  throw MissingFileException();
}
