import 'dart:io';

import 'package:document_throws/src/flutter_index.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('flutterPackages reads package metadata', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('document_throws_flutter_');
    try {
      final root = tempDir.path;
      final binDir = Directory(p.join(root, 'bin'))..createSync();
      File(p.join(binDir.path, 'flutter')).writeAsStringSync('');
      Directory(p.join(root, 'packages')).createSync();
      final pkgDir = Directory(p.join(root, 'packages', 'flutter_test'))
        ..createSync();
      File(p.join(pkgDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: flutter_test\n',
      );
      File(p.join(root, 'version')).writeAsStringSync('3.9.0');

      final version = flutterVersion(root);
      expect(version, isNotNull);
      final packages = flutterPackages(root, version);
      expect(packages, hasLength(1));
      expect(packages.first.name, equals('flutter_test'));
      expect(packages.first.version, equals('3.9.0'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('flutterRoot resolves from sdk root', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('document_throws_flutter_root_');
    try {
      final root = tempDir.path;
      Directory(p.join(root, 'packages')).createSync();
      final binDir = Directory(p.join(root, 'bin'))..createSync();
      File(p.join(binDir.path, 'flutter')).writeAsStringSync('');
      final sdkRoot = Directory(p.join(root, 'bin', 'cache', 'dart-sdk'))
        ..createSync(recursive: true);

      final envRoot = Platform.environment['FLUTTER_ROOT'];
      final expected = (envRoot != null && envRoot.isNotEmpty)
          ? envRoot
          : root;
      expect(flutterRoot(sdkRoot.path), equals(expected));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
