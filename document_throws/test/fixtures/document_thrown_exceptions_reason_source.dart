class BadStateException implements Exception {}

class Sample {
  /// @Throwing(BadStateException, reason: 'bad')
  void annotated() {
    throw BadStateException();
  }
}
