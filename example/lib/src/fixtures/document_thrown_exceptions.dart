class BadStateException implements Exception {}

class Thrower {
  void undocumentedMethod() {
    throw BadStateException();
  }

  /// Throws [BadStateException] when invalid.
  void documentedMethod() {
    throw BadStateException();
  }

  Thrower() {
    throw BadStateException();
  }

  /// Throws [BadStateException] when invalid.
  Thrower.named() {
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
