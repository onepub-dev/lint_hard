class BadStateException implements Exception;

class Thrower {
  new() {
    throw BadStateException();
  }

  /// @Throwing(BadStateException)
  new named() {
    throw BadStateException();
  }

  // Do not add @Throwing to this method, as it exists to test
  // that undocumented methods are correctly identified as missing
  // documentation.
  void undocumentedMethod() {
    throw BadStateException();
  }

  /// @Throwing(BadStateException)
  void documentedMethod() {
    throw BadStateException();
  }
}

// Do not add @Throwing to this method, as it exists to test
// that undocumented methods are correctly identified as missing documentation.
void undocumentedTopLevel() {
  throw BadStateException();
}

/// @Throwing(BadStateException)
void documentedTopLevel() {
  throw BadStateException();
}
