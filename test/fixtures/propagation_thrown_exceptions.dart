part 'propagation_thrown_exceptions.part.dart';

class ParentException implements Exception {}

class ChildException extends ParentException {}

class MissingFileException implements Exception {}

class BadStateException implements Exception {}

// TODO: doc-based propagation disabled; keep for future reinstatement.
// /// Throws [BadStateException] when invalid.
// void documentedThrower() {}
//
// /// Throws [BadStateException] or [MissingFileException].
// void documentedMultiThrower() {}

void topLevelThrower() {
  throw BadStateException();
}

class ThrowingClass {
  void methodThrower() {
    throw BadStateException();
  }

  void parentThrower() {
    throw ChildException();
  }
}

class OtherCtor {
  OtherCtor() {
    throw MissingFileException();
  }
}

class Callers {
  void callsTopLevel() {
    topLevelThrower();
  }

  void callsMethod() {
    ThrowingClass().methodThrower();
  }

  void callsCtor() {
    OtherCtor();
  }

  void catchesParent() {
    try {
      ThrowingClass().parentThrower();
    } on ParentException {
      // handled
    }
  }

  void usesPartFunction() {
    partThrower();
  }

  // TODO: doc-based propagation disabled; keep for future reinstatement.
  // void callsDocThrower() {
  //   documentedThrower();
  // }
  //
  // void callsMultiDocThrower() {
  //   documentedMultiThrower();
  // }

  void callsLocalFunction() {
    void localThrower() {
      throw BadStateException();
    }

    localThrower();
  }
}
