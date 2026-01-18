import 'package:throws_annotations/throws_annotations.dart';

class BadStateException implements Exception {}

class Sample {
  @Throws(BadStateException, reason: 'bad')
  void annotated() {
    throw BadStateException();
  }
}
