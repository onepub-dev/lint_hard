class ExampleWideIndent {
    /// Uses a wider indent for testing.
    ///
    /// @Throwing(
    ///   ArgumentError,
    ///   call: 'example|versionMinor',
    ///   origin: 'example|_versionMinor',
    /// )
    int get versionMinor => _versionMinor();

    int _versionMinor() => throw ArgumentError('bad');
}
