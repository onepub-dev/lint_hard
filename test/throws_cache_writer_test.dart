import 'dart:io';

import 'package:lint_hard/src/throws_cache.dart';
import 'package:lint_hard/src/throws_cache_writer.dart';
import 'package:test/test.dart';

void main() {
  test('writeFileSync uses atomic rename in same directory', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_writer_');
    try {
      final outFile = File('${dir.path}/sample.throws');
      ThrowsCacheWriter.writeFileSync(outFile, {
        'key': ThrowsCacheEntry(thrown: ['BadStateException']),
      });

      expect(outFile.existsSync(), isTrue);
      final tempFiles = dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.tmp'))
          .toList();
      expect(tempFiles, isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
