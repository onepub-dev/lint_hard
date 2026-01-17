class ChModException implements Exception {}

/// Sets the permissions on a file.
void chmod(String path) {
  throw ChModException();
}
