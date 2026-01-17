import 'dart:io';

import 'package:lint_hard/src/throws_cache.dart';
import 'package:lint_hard/src/throws_cache_writer.dart';
import 'package:test/test.dart';

void main() {
  test('cache key builder formats signatures', () {
    final key = ThrowsCacheKeyBuilder.build(
      libraryUri: 'package:foo/foo.dart',
      container: 'Foo',
      name: 'bar',
      parameterTypes: ['int', 'String?'],
    );
    expect(key, 'package:foo/foo.dart|Foo#bar(int,String?)');
  });

  test('cache lookup returns thrown types', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_test_');
    try {
      final file = File('${dir.path}/sample.throws');
      final key = ThrowsCacheKeyBuilder.build(
        libraryUri: 'package:foo/foo.dart',
        container: 'Foo',
        name: 'bar',
        parameterTypes: ['int'],
      );
      final entries = <String, List<String>>{
        key: ['BadStateException', 'MissingFileException'],
      };
      ThrowsCacheWriter.writeFileSync(file, entries);

      final cacheFile = ThrowsCacheFile.openSync(file);
      expect(cacheFile, isNotNull);
      final result = cacheFile!.lookup(key);
      expect(result, ['BadStateException', 'MissingFileException']);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('cache lookup returns empty for unknown key', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_test_');
    try {
      final file = File('${dir.path}/sample.throws');
      final key = ThrowsCacheKeyBuilder.build(
        libraryUri: 'package:foo/foo.dart',
        container: 'Foo',
        name: 'bar',
        parameterTypes: ['int'],
      );
      ThrowsCacheWriter.writeFileSync(file, {key: ['BadStateException']});

      final cacheFile = ThrowsCacheFile.openSync(file);
      expect(cacheFile, isNotNull);
      final result = cacheFile!.lookup('$key#missing');
      expect(result, isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
