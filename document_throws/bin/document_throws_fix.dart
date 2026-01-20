#! /usr/bin/env dart

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:args/args.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'package:document_throws/src/document_thrown_exceptions_fix_utils.dart';
import 'package:document_throws/src/documentation_style.dart';
import 'package:document_throws/src/throws_cache_lookup.dart';
import 'package:document_throws/src/version/version.g.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information.',
    )
    ..addFlag(
      'origin',
      negatable: false,
      help: 'Include call/origin provenance in @Throwing.',
    )
    ..addFlag(
      'always-add',
      negatable: false,
      help: 'Add @Throwing even when doc comments mention the exception.',
    )
    ..addFlag(
      'annotation',
      negatable: false,
      help: 'Use @Throwing annotations instead of doc comments.',
    )
    ..addFlag(
      'doc-comment',
      negatable: false,
      help: 'Force doc comment output (default).',
    );

  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (error) {
    _printUsage(parser, error: error.message);
    exitCode = 64;
    return;
  }

  if (parsed['help'] == true) {
    _printUsage(parser);
    return;
  }

  stdout.writeln('document_throws_fix $packageVersion');

  final root = Directory.current.path;
  final includeSource = parsed['origin'] as bool;
  final alwaysAdd = parsed['always-add'] as bool;
  final forceAnnotation = parsed['annotation'] as bool;
  final forceDocComment = parsed['doc-comment'] as bool;
  if (forceAnnotation && forceDocComment) {
    _printUsage(parser, error: 'Choose one of --annotation or --doc-comment.');
    exitCode = 64;
    return;
  }
  final forcedStyle = forceAnnotation
      ? DocumentationStyle.annotation
      : (forceDocComment ? DocumentationStyle.docComment : null);
  final patterns = parsed.rest;
  final summaryNotes = <String>[];
  if (includeSource) {
    summaryNotes.add(
      'Including provenance in @Throwing annotations (--origin).',
    );
    summaryNotes.add(
      'To remove provenance, rerun document_throws_fix without --origin to '
      'rewrite existing @Throwing entries without provenance.',
    );
  }
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
  final styleByRoot = <String, DocumentationStyle>{};

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
    final documentationStyle = forcedStyle ??
        (rootPath == null
            ? DocumentationStyle.docComment
            : styleByRoot.putIfAbsent(
                rootPath,
                () => documentationStyleForRoot(rootPath),
              ));
    final editsByFile = documentThrownExceptionEdits(
      unitResult,
      libraryResult.units,
      externalLookup: externalLookup,
      includeSource: includeSource,
      honorDocMentions: !alwaysAdd,
      documentationStyle: documentationStyle,
    );
    if (editsByFile.isEmpty) continue;

    for (final entry in editsByFile.entries) {
      editsByPath.putIfAbsent(entry.key, () => <SourceEdit>[])
        ..addAll(entry.value);
    }
  }

  var updatedCount = 0;
  for (final entry in editsByPath.entries) {
    final edits = entry.value..sort((a, b) => b.offset.compareTo(a.offset));
    final content = await File(entry.key).readAsString();
    final updated = SourceEdit.applySequence(content, edits);
    if (updated != content) {
      await File(entry.key).writeAsString(updated);
      updatedCount++;
    }
  }

  stdout.writeln('Updated $updatedCount file(s).');
  for (final note in summaryNotes) {
    stdout.writeln(note);
  }
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

void _printUsage(ArgParser parser, {String? error}) {
  if (error != null && error.isNotEmpty) {
    stderr.writeln(error);
    stderr.writeln('');
  }
  stdout.writeln('Apply document_throws fixes to Dart files.');
  stdout.writeln('');
  stdout.writeln('Usage: document_throws_fix [options] [<glob> ...]');
  stdout.writeln('');
  stdout.writeln('If no globs are provided, all .dart files under the');
  stdout.writeln('current directory are processed.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(parser.usage);
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln("  dt_fix");
  stdout.writeln("  dt_fix --origin");
  stdout.writeln("  dt_fix 'lib/**/*.dart'");
  stdout.writeln("  dt_fix 'lib/**/*.dart' 'test/**/*.dart'");
}
