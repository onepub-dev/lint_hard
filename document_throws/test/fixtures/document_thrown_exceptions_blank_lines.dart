/// Provide a very simple mechanism to backup a single file.
///
/// The backup is placed in '.bak' subdirectory under the passed
/// [pathToFile]'s directory.
///
/// @Throwing(
///   ArgumentError,
///   call: 'dcli_core|backupFile',
///   origin: 'dcli_core|exists',
/// )
/// @Throwing(ArgumentError)
void backupFile(String pathToFile) {
  throw ArgumentError('bad');
}
