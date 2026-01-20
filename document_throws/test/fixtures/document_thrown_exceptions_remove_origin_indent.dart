class Example {
  /// From 2.10 onwards we use the dart compile option rather than dart2native.
  ///
  /// @Throwing(
  ///   ArgumentError,
  ///   call: 'example|versionMinor',
  ///   origin: 'example|_versionMinor',
  /// )
  int get versionMinor => _versionMinor();

  int _versionMinor() => throw ArgumentError('bad');
}
