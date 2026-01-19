import 'package:document_throws/src/throws_cache_lookup.dart';
import 'package:document_throws/src/throws_index_up_to_date.dart';
import 'package:test/test.dart';

void main() {
  test('labels missing sdk first', () {
    final missing = MissingThrowsCaches(
      sdkMissing: true,
      missingPackages: ['path', 'yaml'],
    );

    expect(firstMissingCacheLabel(missing), equals('sdk'));
  });

  test('labels first missing package when sdk present', () {
    final missing = MissingThrowsCaches(
      sdkMissing: false,
      missingPackages: ['path', 'yaml'],
    );

    expect(firstMissingCacheLabel(missing), equals('path'));
  });

  test('returns null when nothing missing', () {
    const missing = MissingThrowsCaches(
      sdkMissing: false,
      missingPackages: [],
    );

    expect(firstMissingCacheLabel(missing), isNull);
  });
}
