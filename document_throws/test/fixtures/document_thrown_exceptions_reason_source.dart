import 'package:document_throws/document_throws.dart';

class BadStateException implements Exception {}

class Sample {
  @Throws(BadStateException, reason: 'bad')
  void annotated() {
    throw BadStateException();
  }
}
