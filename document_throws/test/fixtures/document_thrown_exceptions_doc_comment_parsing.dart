class FooException implements Exception {}
class BarException implements Exception {}
class BazException implements Exception {}
class GenericException<T> implements Exception {}

class DocParsingSample {
  /// @Throwing(FooException)
  void singleLine() {}

  /**
   * @Throwing(BarException)
   */
  void blockDoc() {}

  /// @Throwing(
  ///   BazException,
  ///   reason: 'Bad',
  /// )
  void multiLine() {}

  /// @Throwing(GenericException<String>)
  void genericType() {}

  /// @Throwing(FooException)
  /// @Throwing(BarException)
  void multipleTags() {}

  /// @Throwing()
  void missingArg() {}

  /// @Throwing(
  void missingParen() {}

  /// @Throwing
  void missingOpenParen() {}
}
