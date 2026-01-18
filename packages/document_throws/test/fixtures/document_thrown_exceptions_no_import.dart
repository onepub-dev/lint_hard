class BadStateException implements Exception {}

void undocumentedTopLevel() {
  throw BadStateException();
}
