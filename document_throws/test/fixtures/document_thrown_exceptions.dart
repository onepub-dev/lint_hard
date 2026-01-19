// ignore_for_file: dead_code

class BadStateException implements Exception {}
class BadState implements Exception {}
class InvalidArg implements Exception {}
class InvalidArgException implements Exception {}
class MissingFile implements Exception {}
class MissingFileException implements Exception {}

class Sample {
  /// @Throwing(BadStateException)
  void documentedMethod() {
    throw BadStateException();
  }

  void undocumentedMethod() {
    throw BadStateException();
  }

  void commentThrowMethod() {
    // throw StateException();
  }

  void usesRegExp() {
    RegExp('[');
  }

  /// @Throwing(MissingFileException)
  void documentedMultiLineThrows() {
    throw MissingFileException();
  }

  /// @Throwing(BadStateException)
  void documentedThrowsWithArticle() {
    throw BadStateException();
  }

  /// @Throwing(MissingFileException)
  void documentedThrowsMidSentence() {
    throw MissingFileException();
  }

  /// @Throwing(MissingFileException, reason: 'Missing input')
  void documentedThrowsWithReason() {
    throw MissingFileException();
  }

  /// Throws [BadStateException].
  void mentionedThrowWithoutTag() {
    throw BadStateException();
  }

  /// Throws [BadStateException].
  void mentionedNoThrow() {}

  /// Run dart pub global activate for a package located in [path]
  /// relative to the current directory.
  void mentionedNonThrow(String path) {}

  /// @Throwing(BadStateException)
  void annotatedMissingException() {
    throw BadStateException();
    throw MissingFileException();
  }

  /// @Throwing(BadStateException, reason: 'bad')
  void annotatedMissingExceptionWithSpec() {
    throw BadStateException();
    throw MissingFileException();
  }

  /// @Throwing(MissingFileException)
  /// @Throwing(BadStateException)
  /// @Throwing(InvalidArgException)
  void documentedThrowsList() {
    throw MissingFileException();
  }

  /// @Throwing(MissingFile)
  /// @Throwing(BadState)
  /// @Throwing(InvalidArg)
  void documentedThrowsListWithSpaces() {
    if (true) {
      throw MissingFile();
    } else if (DateTime.now().isUtc) {
      throw BadState();
    } else {
      throw InvalidArg();
    }
  }

  void throwCaughtWithoutOn() {
    try {
      throw BadStateException();
    } catch (e) {
      e.toString();
    }
  }

  void throwCaughtWithOn() {
    try {
      throw BadStateException();
    } on Exception catch (e) {
      e.toString();
    }
  }

  void throwCaughtWithSameOn() {
    try {
      throw BadStateException();
    } on BadStateException {
      // handled
    }
  }

  void throwCaughtWithRethrow() {
    try {
      throw BadStateException();
    } on Exception {
      rethrow;
    }
  }

  void undocumentedMultipleThrows() {
    if (DateTime.now().isUtc) {
      throw BadStateException();
    }
    throw MissingFileException();
  }

  void duplicatedThrows() {
    throw BadStateException();
    if (DateTime.now().isUtc) {
      throw BadStateException();
    }
  }

  /// @Throwing(BadStateException)
  void documentedThrowsNoBody() {}

  void callerUsesDocThrows() {
    documentedThrowsNoBody();
  }

  void callerUsesThrowingMethod() {
    undocumentedMethod();
  }

  void callerCatchesThrowingMethod() {
    try {
      undocumentedMethod();
    } on BadStateException {
      // handled
    }
  }

  /// @Throwing(BadStateException)
  Sample.named() {
    throw BadStateException();
  }

  Sample() {
    throw BadStateException();
  }
}

/// @Throwing(BadStateException)
void documentedTopLevel() {
  throw BadStateException();
}

void undocumentedTopLevel() {
  throw BadStateException();
}
