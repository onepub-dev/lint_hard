#! /usr/bin/env dart

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'package:lint_hard/src/document_thrown_exceptions_fix_utils.dart';
import 'package:lint_hard/src/throws_cache_lookup.dart';
import 'package:lint_hard/src/version/version.g.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    _printUsage();
    return;
  }

  stdout.writeln('lint_hard_fix $packageVersion');

  final root = Directory.current.path;
  final patterns = args.where((arg) => !arg.startsWith('-')).toList();
  final files = await _collectDartFiles(patterns, root);
  if (files.isEmpty) {
    stderr.writeln('No Dart files matched.');
    exitCode = 1;
    return;
  }

  final collection = AnalysisContextCollection(includedPaths: [root]);
  final libraryCache = <String, ResolvedLibraryResult>{};
  final editsByPath = <String, List<SourceEdit>>{};
  final lookupByRoot = <String, ThrowsCacheLookup?>{};

  for (final filePath in files) {
    final context = collection.contextFor(filePath);
    final session = context.currentSession;
    final unitResult = await session.getResolvedUnit(filePath);
    if (unitResult is! ResolvedUnitResult) continue;

    final libraryResult = await _resolvedLibraryForFile(
      session,
      unitResult,
      libraryCache,
    );
    if (libraryResult == null) continue;

    final rootPath = findProjectRoot(filePath);
    final externalLookup = rootPath == null
        ? null
        : lookupByRoot.putIfAbsent(
            rootPath,
            () => ThrowsCacheLookup.forProjectRoot(rootPath),
          );
    final edits = documentThrownExceptionEdits(
      unitResult,
      libraryResult.units,
      externalLookup: externalLookup,
    );
    if (edits.isEmpty) continue;

    edits.sort((a, b) => a.offset.compareTo(b.offset));
    editsByPath[filePath] = edits;
  }

  var updatedCount = 0;
  for (final entry in editsByPath.entries) {
    final content = await File(entry.key).readAsString();
    final updated = SourceEdit.applySequence(content, entry.value);
    if (updated != content) {
      await File(entry.key).writeAsString(updated);
      updatedCount++;
    }
  }

  stdout.writeln('Updated $updatedCount file(s).');
}

Future<List<String>> _collectDartFiles(
  List<String> patterns,
  String root,
) async {
  final files = <String>{};
  if (patterns.isEmpty) {
    await for (final entity in Directory(root).list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (_isIgnoredPath(entity.path, root)) continue;
      files.add(entity.path);
    }
    return files.toList()..sort();
  }

  for (final pattern in patterns) {
    final glob = Glob(pattern);
    final entities = p.isAbsolute(pattern)
        ? glob.listSync(followLinks: false)
        : glob.listSync(root: root, followLinks: false);
    for (final entity in entities) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (_isIgnoredPath(entity.path, root)) continue;
      files.add(p.normalize(entity.path));
    }
  }

  return files.toList()..sort();
}

bool _isIgnoredPath(String path, String root) {
  final relative = p.relative(path, from: root);
  final parts = p.split(relative);
  for (final part in parts) {
    if (part.isEmpty) continue;
    if (part == '.dart_tool' || part == 'build' || part == '.git') return true;
    if (part.startsWith('.')) return true;
  }
  return false;
}

Future<ResolvedLibraryResult?> _resolvedLibraryForFile(
  AnalysisSession session,
  ResolvedUnitResult unitResult,
  Map<String, ResolvedLibraryResult> cache,
) async {
  final libraryPath = unitResult.libraryElement.firstFragment.source.fullName;
  final cached = cache[libraryPath];
  if (cached != null) return cached;

  final libraryResult =
      await session.getResolvedLibraryContaining(unitResult.path);
  if (libraryResult is! ResolvedLibraryResult) return null;
  cache[libraryPath] = libraryResult;
  return libraryResult;
}

void _printUsage() {
  stdout.writeln('Apply lint_hard fixes to Dart files.');
  stdout.writeln('');
  stdout.writeln('Usage: lint_hard_fix [<glob> ...]');
  stdout.writeln('');
  stdout.writeln('If no globs are provided, all .dart files under the');
  stdout.writeln('current directory are processed.');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln("  lint_hard_fix 'lib/**/*.dart'");
  stdout.writeln("  lint_hard_fix 'lib/**/*.dart' 'test/**/*.dart'");
}
