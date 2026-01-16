// ignore_for_file: dead_code

class BadStateException implements Exception {}
class BadState implements Exception {}
class InvalidArg implements Exception {}
class InvalidArgException implements Exception {}
class MissingFile implements Exception {}
class MissingFileException implements Exception {}

class Sample {
  /// Throws [BadStateException] when invalid.
  void documentedMethod() {
    throw BadStateException();
  }

  void undocumentedMethod() {
    throw BadStateException();
  }

  void commentThrowMethod() {
    // throw StateException();
  }

  /// When the file doesn't exist throws a
  /// [MissingFileException] during processing.
  void documentedMultiLineThrows() {
    throw MissingFileException();
  }

  /// Throws a [BadStateException] when invalid.
  void documentedThrowsWithArticle() {
    throw BadStateException();
  }

  /// When the file doesn't exist it throws a [MissingFileException].
  void documentedThrowsMidSentence() {
    throw MissingFileException();
  }

  /// When an error occurs we throw [MissingFileException] or
  /// [BadStateException] or [InvalidArgException].
  void documentedThrowsList() {
    throw MissingFileException();
  }

  /// When an error occurs we throw [Missing File] or [BadState] or
  /// [Invalid Arg].
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
