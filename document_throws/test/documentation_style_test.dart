import 'dart:io';

import 'package:document_throws/src/documentation_style.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('defaults to doc comments without analysis_options', () {
    final dir = Directory.systemTemp.createTempSync(
      'document_throws_style_',
    );
    try {
      expect(
        documentationStyleForRoot(dir.path),
        DocumentationStyle.docComment,
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('reads annotation style from analysis_options', () {
    final dir = Directory.systemTemp.createTempSync(
      'document_throws_style_',
    );
    try {
      final optionsPath = p.join(dir.path, 'analysis_options.yaml');
      File(optionsPath).writeAsStringSync(
        'document_throws:\n  documentation_style: annotation\n',
      );
      expect(
        documentationStyleForRoot(dir.path),
        DocumentationStyle.annotation,
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
