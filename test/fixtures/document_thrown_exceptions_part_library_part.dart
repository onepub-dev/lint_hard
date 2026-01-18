part of 'document_thrown_exceptions_part_library.dart';

class BadStateException implements Exception {}

void partFunction() {
  throw BadStateException();
}
