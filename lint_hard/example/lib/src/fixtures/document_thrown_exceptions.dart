import 'package:lint_hard/lint_hard.dart';

class BadStateException implements Exception {}

class Thrower {
  Thrower() {
    throw BadStateException();
  }

  /// @Throwing(BadStateException)
  Thrower.named() {
    throw BadStateException();
  }

  void undocumentedMethod() {
    throw BadStateException();
  }

  /// @Throwing(BadStateException)
  void documentedMethod() {
    throw BadStateException();
  }
}

void undocumentedTopLevel() {
  throw BadStateException();
}

/// @Throwing(BadStateException)
void documentedTopLevel() {
  throw BadStateException();
}
