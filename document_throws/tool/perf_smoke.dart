import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:document_throws/src/document_thrown_exceptions_fix_utils.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final root = Directory.current.path;
  final fixturePath = p.join(
    root,
    'test',
    'fixtures',
    'document_thrown_exceptions.dart',
  );
  final fixtureFile = File(fixturePath);
  if (!fixtureFile.existsSync()) {
    stderr.writeln('Fixture not found: $fixturePath');
    exit(1);
  }

  final collection = AnalysisContextCollection(
    includedPaths: [root],
  );
  final context = collection.contextFor(fixturePath);
  final session = context.currentSession;
  final unitResult = await session.getResolvedUnit(fixturePath);
  final libraryResult = await session.getResolvedLibrary(fixturePath);
  if (unitResult is! ResolvedUnitResult ||
      libraryResult is! ResolvedLibraryResult) {
    stderr.writeln('Failed to resolve fixture for performance run.');
    await collection.dispose();
    exit(1);
  }

  const runs = 50;
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    documentThrownExceptionEdits(
      unitResult,
      libraryResult.units,
    );
  }
  stopwatch.stop();
  await collection.dispose();

  final totalMs = stopwatch.elapsedMilliseconds;
  final avgMs = totalMs / runs;
  stdout.writeln('Runs: $runs');
  stdout.writeln('Total: ${totalMs}ms');
  stdout.writeln('Average: ${avgMs.toStringAsFixed(2)}ms');
}
