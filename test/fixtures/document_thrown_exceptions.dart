class BadStateException implements Exception {}

class Sample {
  /// Throws [BadStateException] when invalid.
  void documentedMethod() {
    throw BadStateException();
  }

  void undocumentedMethod() {
    throw BadStateException();
  }

  /// Throws [BadStateException] when invalid.
  Sample.named() {
    throw BadStateException();
  }

  Sample() {
    throw BadStateException();
  }
}

/// Throws [BadStateException] when invalid.
void documentedTopLevel() {
  throw BadStateException();
}

void undocumentedTopLevel() {
  throw BadStateException();
}
