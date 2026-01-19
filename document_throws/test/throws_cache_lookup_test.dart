import 'dart:io';

import 'package:document_throws/src/throws_cache.dart';
import 'package:document_throws/src/throws_cache_lookup.dart';
import 'package:document_throws/src/throws_cache_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('missingCaches reports missing package cache', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_lookup_');
    try {
      final root = p.join(dir.path, 'project');
      Directory(root).createSync(recursive: true);
      File(p.join(root, 'pubspec.lock')).writeAsStringSync('''
packages:
  foo:
    version: "1.2.3"
    source: hosted
    description:
      url: "https://pub.dev"
''');
      final cacheRoot = p.join(dir.path, 'pub-cache', 'document_throws', 'cache');
      final lookup = ThrowsCacheLookup.forProjectRootWithCache(
        root,
        cacheRoot,
      );
      expect(lookup, isNotNull);

      final missing = lookup!.missingCaches();
      expect(missing.missingPackages, contains('foo'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('missingCaches reports present package cache', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_lookup_');
    try {
      final root = p.join(dir.path, 'project');
      Directory(root).createSync(recursive: true);
      File(p.join(root, 'pubspec.lock')).writeAsStringSync('''
packages:
  foo:
    version: "1.2.3"
    source: hosted
    description:
      url: "https://pub.dev"
''');
      final cacheRoot = p.join(dir.path, 'pub-cache', 'document_throws', 'cache');
      final cacheFile = File(p.join(
        cacheRoot,
        'throws',
        'v1',
        'package',
        'foo',
        'hosted-pub.dev',
        '1.2.3.throws',
      ));
      ThrowsCacheWriter.writeFileSync(cacheFile, {
        'key': ThrowsCacheEntry(thrown: ['BadStateException']),
      });

      final lookup = ThrowsCacheLookup.forProjectRootWithCache(
        root,
        cacheRoot,
      );
      expect(lookup, isNotNull);

      final missing = lookup!.missingCaches();
      expect(missing.missingPackages, isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('missingCaches reports missing sdk cache', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_lookup_');
    try {
      final root = p.join(dir.path, 'project');
      Directory(root).createSync(recursive: true);
      File(p.join(root, 'pubspec.lock')).writeAsStringSync('''
packages:
  foo:
    version: "1.2.3"
    source: hosted
    description:
      url: "https://pub.dev"
''');
      final cacheRoot = p.join(dir.path, 'pub-cache', 'document_throws', 'cache');
      final lookup = ThrowsCacheLookup.forProjectRootWithCache(
        root,
        cacheRoot,
      );
      expect(lookup, isNotNull);

      final missing = lookup!.missingCaches();
      expect(missing.sdkMissing, isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('missingCaches reports present sdk cache', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_lookup_');
    try {
      final root = p.join(dir.path, 'project');
      Directory(root).createSync(recursive: true);
      File(p.join(root, 'pubspec.lock')).writeAsStringSync('''
packages:
  foo:
    version: "1.2.3"
    source: hosted
    description:
      url: "https://pub.dev"
''');
      final cacheRoot = p.join(dir.path, 'pub-cache', 'document_throws', 'cache');
      final sdkVersion = Platform.version.split(' ').first;
      final sdkFile = File(p.join(
        cacheRoot,
        'throws',
        'v1',
        'sdk',
        '$sdkVersion.throws',
      ));
      ThrowsCacheWriter.writeFileSync(sdkFile, {
        'key': ThrowsCacheEntry(thrown: ['BadStateException']),
      });

      final lookup = ThrowsCacheLookup.forProjectRootWithCache(
        root,
        cacheRoot,
      );
      expect(lookup, isNotNull);

      final missing = lookup!.missingCaches();
      expect(missing.sdkMissing, isFalse);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('missingCaches uses flutter version for sdk packages', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_lookup_');
    try {
      final cacheRoot = p.join(dir.path, 'pub-cache', 'document_throws', 'cache');
      final flutterFile = File(p.join(
        cacheRoot,
        'throws',
        'v1',
        'package',
        'flutter',
        'sdk',
        '3.3.0.throws',
      ));
      ThrowsCacheWriter.writeFileSync(flutterFile, {
        'key': ThrowsCacheEntry(thrown: ['BadStateException']),
      });

      final lookup = ThrowsCacheLookup(
        cache: ThrowsCache(cacheRoot),
        packageVersions: const {'flutter': '0.0.0'},
        packageSources: const {'flutter': 'sdk'},
        sdkVersion: null,
        sdkRoot: null,
        flutterVersion: '3.3.0',
      );
      final missing = lookup.missingCaches();
      expect(missing.missingPackages, isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('forProjectRootWithCache reads transitive versions from pubspec.lock', () {
    final dir = Directory.systemTemp.createTempSync('throws_cache_lookup_');
    try {
      final root = p.join(dir.path, 'project');
      Directory(root).createSync(recursive: true);
      File(p.join(root, 'pubspec.lock')).writeAsStringSync('''
packages:
  direct_pkg:
    dependency: "direct main"
    version: "1.0.0"
    source: hosted
    description:
      url: "https://pub.dev"
  transitive_pkg:
    dependency: transitive
    version: "2.1.0"
    source: hosted
    description:
      url: "https://pub.dev"
''');
      final cacheRoot = p.join(dir.path, 'pub-cache', 'document_throws', 'cache');

      final lookup = ThrowsCacheLookup.forProjectRootWithCache(
        root,
        cacheRoot,
      );
      expect(lookup, isNotNull);
      expect(lookup!.packageVersions['direct_pkg'], equals('1.0.0'));
      expect(lookup.packageVersions['transitive_pkg'], equals('2.1.0'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
