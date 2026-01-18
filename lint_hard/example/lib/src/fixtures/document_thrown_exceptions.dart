import 'package:lint_hard/lint_hard.dart';

class BadStateException implements Exception {}

class Thrower {
  Thrower() {
    throw BadStateException();
  }

  /// Throws [BadStateException] when invalid.
  @Throws(BadStateException)
  Thrower.named() {
    throw BadStateException();
  }

  void undocumentedMethod() {
    throw BadStateException();
  }

  /// Throws [BadStateException] when invalid.
  void documentedMethod() {
    throw BadStateException();
  }
}

void undocumentedTopLevel() {
  throw BadStateException();
}

/// Throws [BadStateException] when invalid.
void documentedTopLevel() {
  throw BadStateException();
}
