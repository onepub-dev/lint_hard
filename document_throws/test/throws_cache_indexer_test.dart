import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:document_throws/src/throws_cache_indexer.dart';
import 'package:test/test.dart';

void main() {
  test('indexer resolves throws across package libraries', () async {
    final fixturePath = File(
      'test/fixtures/indexer_cross_library_a.dart',
    ).absolute.path;
    final otherPath = File(
      'test/fixtures/indexer_cross_library_b.dart',
    ).absolute.path;
    final collection = AnalysisContextCollection(
      includedPaths: [fixturePath],
    );
    final context = collection.contextFor(fixturePath);
    final session = context.currentSession;
    final libraryResult = await session.getResolvedLibraryContaining(
      fixturePath,
    );
    if (libraryResult is! ResolvedLibraryResult) {
      throw StateError('Failed to resolve library for $fixturePath');
    }
    final unitsByPath = <String, CompilationUnit>{};
    for (final unit in libraryResult.units) {
      unitsByPath[unit.path] = unit.unit;
    }
    final otherResult = await session.getResolvedLibraryContaining(otherPath);
    if (otherResult is ResolvedLibraryResult) {
      for (final unit in otherResult.units) {
        unitsByPath[unit.path] = unit.unit;
      }
    }

    final entries = buildThrowsIndex(
      libraryResult,
      unitsByPath: unitsByPath,
    );
    final matches = entries.entries.where(
      (entry) => entry.key.contains('crossLibraryCaller('),
    );
    expect(matches, isNotEmpty);
    final entry = matches.first.value;
    expect(entry.thrown, contains('CrossLibraryException'));
    await collection.dispose();
  });
}
