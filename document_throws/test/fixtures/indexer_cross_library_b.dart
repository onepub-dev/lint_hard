class CrossLibraryException implements Exception {}

void crossLibraryCallee() {
  throw CrossLibraryException();
}
