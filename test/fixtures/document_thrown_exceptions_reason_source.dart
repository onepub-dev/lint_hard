import 'package:lint_hard/throws.dart';

class BadStateException implements Exception {}

class Sample {
  @Throws(BadStateException, reason: 'bad')
  void annotated() {
    throw BadStateException();
  }
}
