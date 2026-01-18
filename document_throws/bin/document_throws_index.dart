#! /usr/bin/env dart

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:document_throws/src/throws_cache.dart';
import 'package:document_throws/src/throws_cache_indexer.dart';
import 'package:document_throws/src/throws_cache_writer.dart';
import 'package:document_throws/src/version/version.g.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    _printUsage();
    return;
  }

  final root = Directory.current.path;
  final quiet = args.contains('--quiet') || args.contains('-q');
  final outputRoot = _argValue(args, '--output') ?? _defaultCacheRoot();
  final includeSdk = !args.contains('--no-sdk');
  final includeFlutter = !args.contains('--no-flutter');
  final includePackages = !args.contains('--no-packages');
  final sdkPath = _sdkPath();
  void log(String message) {
    if (!quiet) stdout.writeln(message);
  }

  log('document_throws_index starting');
  log('Version: $packageVersion');
  log('Output cache: $outputRoot');
  log('Packages: ${includePackages ? 'on' : 'off'}');
  log('SDK: ${includeSdk ? 'on' : 'off'}');
  log('Flutter: ${includeFlutter ? 'on' : 'off'}');

  if (includePackages) {
    final lockFile = File(p.join(root, 'pubspec.lock'));
    if (lockFile.existsSync()) {
      final packages = _readPackageLock(lockFile);
      log('Found ${packages.length} package(s) to index.');
      var indexed = 0;
      for (final package in packages) {
        final packageRoot = _packageRoot(package);
        if (packageRoot == null) {
          log('Skipping ${package.name} (no path)');
          continue;
        }
        indexed++;
        log(
          'Indexing ${package.name} ${package.version} '
          '($indexed/${packages.length})',
        );
        final entries = await _indexPackage(
          packageRoot,
          sdkPath,
          packageName: package.name,
          log: log,
        );
        final outFile = File(
          p.join(
            outputRoot,
            'throws',
            'v1',
            'package',
            package.name,
            package.sourceId,
            '${package.version}.throws',
          ),
        );
        ThrowsCacheWriter.writeFileSync(outFile, entries);
        log(
          'Wrote ${entries.length} entries to ${outFile.path}',
        );
      }
    } else {
      log('pubspec.lock not found; skipping packages.');
    }
  }

  if (includeSdk) {
    final sdkVersion = _sdkVersion();
    final sdkRoot = sdkPath ?? _sdkRootFromExecutable();
    if (sdkRoot == null) {
      log('Unable to determine SDK path; skipping SDK index.');
      return;
    }
    log('Indexing SDK $sdkVersion');
    final sdkEntries = await _indexSdk(sdkRoot, sdkPath, log: log);
    final outFile = File(
      p.join(outputRoot, 'throws', 'v1', 'sdk', '$sdkVersion.throws'),
    );
    ThrowsCacheWriter.writeFileSync(outFile, sdkEntries);
    log(
      'Wrote ${sdkEntries.length} entries to ${outFile.path}',
    );
  }

  if (includeFlutter) {
    final sdkRoot = sdkPath ?? _sdkRootFromExecutable();
    final flutterRoot = _flutterRoot(sdkRoot);
    if (flutterRoot == null) {
      log('Unable to determine Flutter SDK path; skipping Flutter index.');
    } else {
      final flutterVersion = _flutterVersion(flutterRoot);
      log('Indexing Flutter SDK $flutterVersion');
      final packages = _flutterPackages(flutterRoot, flutterVersion);
      if (packages.isEmpty) {
        log(
          '  No Flutter packages found under '
          '${p.join(flutterRoot, 'packages')}',
        );
      } else {
        var indexed = 0;
        for (final package in packages) {
          indexed++;
        log(
          'Indexing Flutter package ${package.name} ${package.version} '
          '($indexed/${packages.length})',
        );
          final entries = await _indexPackage(
            package.path,
            sdkPath,
            packageName: package.name,
            log: log,
          );
          final outFile = File(
            p.join(
              outputRoot,
              'throws',
              'v1',
              'package',
              package.name,
              'sdk',
              '${package.version}.throws',
            ),
          );
          ThrowsCacheWriter.writeFileSync(outFile, entries);
          log(
            'Wrote ${entries.length} entries to ${outFile.path}',
          );
        }
      }
    }
  }
}

Future<Map<String, ThrowsCacheEntry>> _indexPackage(
  String packageRoot,
  String? sdkPath, {
  String? packageName,
  void Function(String message)? log,
}) async {
  final libDir = Directory(p.join(packageRoot, 'lib'));
  if (!libDir.existsSync()) {
    log?.call('  No lib/ directory in $packageRoot');
    return const <String, ThrowsCacheEntry>{};
  }
  final files = _collectDartFiles(libDir);
  log?.call('  Scanning ${libDir.path}');
  return _indexLibraries(
    libDir.path,
    files,
    sdkPath,
    packageName: packageName,
    log: log,
  );
}

Future<Map<String, ThrowsCacheEntry>> _indexSdk(
  String sdkRoot,
  String? sdkPath, {
  void Function(String message)? log,
}) async {
  final libDir = Directory(p.join(sdkRoot, 'lib'));
  if (!libDir.existsSync()) {
    log?.call('  No lib/ directory in SDK at $sdkRoot');
    return const <String, ThrowsCacheEntry>{};
  }
  final files = _collectDartFiles(libDir);
  log?.call('  Scanning ${libDir.path}');
  return _indexLibraries(libDir.path, files, sdkPath, log: log);
}

Future<Map<String, ThrowsCacheEntry>> _indexLibraries(
  String rootPath,
  List<String> files,
  String? sdkPath, {
  String? packageName,
  void Function(String message)? log,
}) async {
  if (files.isEmpty) return const <String, ThrowsCacheEntry>{};
  final collection = AnalysisContextCollection(
    includedPaths: [p.normalize(rootPath)],
    sdkPath: sdkPath,
  );
  final context = collection.contextFor(files.first);
  final session = context.currentSession;
  final entries = <String, ThrowsCacheEntry>{};
  final seenLibraries = <String>{};
  log?.call('  Resolving libraries...');

  for (final file in files) {
    final resolved = await session.getResolvedLibraryContaining(file);
    if (resolved is! ResolvedLibraryResult) continue;
    final libraryPath = resolved.element.firstFragment.source.fullName;
    if (!seenLibraries.add(libraryPath)) continue;
    final libraryUri = _libraryUriFor(resolved, rootPath, packageName);
    entries.addAll(buildThrowsIndex(resolved, libraryUri: libraryUri));
  }
  await collection.dispose();
  return entries;
}

List<String> _collectDartFiles(Directory rootDir) {
  final files = <String>[];
  for (final entity
      in rootDir.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(p.normalize(entity.path));
    }
  }
  return files;
}

String? _sdkPath() {
  final value = Platform.environment['DART_SDK'];
  return value == null || value.isEmpty ? null : value;
}

String _sdkVersion() {
  final full = Platform.version;
  final parts = full.split(' ');
  return parts.isEmpty ? 'unknown' : parts.first;
}

String _libraryUriFor(
  ResolvedLibraryResult library,
  String rootPath,
  String? packageName,
) {
  final source = library.element.firstFragment.source;
  final uri = source.uri;
  if (uri.scheme == 'package' || uri.scheme == 'dart') {
    return uri.toString();
  }
  final libRoot = p.normalize(rootPath);
  final filePath = p.normalize(source.fullName);
  if (packageName != null) {
    if (!p.isWithin(libRoot, filePath)) {
      return uri.toString();
    }
    final relative = p.relative(filePath, from: libRoot);
    final relativeParts = p.split(relative);
    final posixRelative = p.posix.joinAll(relativeParts);
    return 'package:$packageName/$posixRelative';
  }
  if (!p.isWithin(libRoot, filePath)) {
    return uri.toString();
  }
  final relative = p.relative(filePath, from: libRoot);
  final relativeParts = p.split(relative);
  final posixRelative = p.posix.joinAll(relativeParts);
  return 'dart:$posixRelative';
}

String? _sdkRootFromExecutable() {
  final exec = Platform.resolvedExecutable;
  final binDir = File(exec).parent;
  return binDir.parent.path;
}

String? _flutterRoot(String? sdkRoot) {
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null && envRoot.isNotEmpty) {
    final dir = Directory(envRoot);
    if (dir.existsSync()) return dir.path;
  }

  if (sdkRoot == null) return null;
  final candidate = p.normalize(p.join(sdkRoot, '..', '..', '..'));
  final packagesDir = Directory(p.join(candidate, 'packages'));
  final flutterBin = File(p.join(candidate, 'bin', 'flutter'));
  if (packagesDir.existsSync() && flutterBin.existsSync()) {
    return candidate;
  }
  return null;
}

String _flutterVersion(String flutterRoot) {
  final versionFile = File(p.join(flutterRoot, 'version'));
  if (versionFile.existsSync()) {
    final value = versionFile.readAsStringSync().trim();
    if (value.isNotEmpty) return value;
  }
  return 'unknown';
}

List<_FlutterPackage> _flutterPackages(
  String flutterRoot,
  String flutterVersion,
) {
  final packagesDir = Directory(p.join(flutterRoot, 'packages'));
  if (!packagesDir.existsSync()) return const <_FlutterPackage>[];
  final results = <_FlutterPackage>[];
  for (final entity in packagesDir.listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final pubspec = File(p.join(entity.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) continue;
    final info = _readFlutterPackage(pubspec, entity.path, flutterVersion);
    if (info != null) results.add(info);
  }
  return results;
}

_FlutterPackage? _readFlutterPackage(
  File pubspec,
  String packagePath,
  String flutterVersion,
) {
  final doc = loadYaml(pubspec.readAsStringSync());
  if (doc is! YamlMap) return null;
  final name = doc['name']?.toString();
  if (name == null || name.isEmpty) return null;
  return _FlutterPackage(
    name: name,
    path: packagePath,
    version: flutterVersion,
  );
}

String? _argValue(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }
  return null;
}

List<_LockedPackage> _readPackageLock(File lockFile) {
  final doc = loadYaml(lockFile.readAsStringSync());
  if (doc is! YamlMap) return const <_LockedPackage>[];
  final packages = doc['packages'];
  if (packages is! YamlMap) return const <_LockedPackage>[];
  final results = <_LockedPackage>[];

  for (final entry in packages.entries) {
    final name = entry.key.toString();
    final value = entry.value;
    if (value is! YamlMap) continue;
    final version = value['version']?.toString() ?? '';
    final source = value['source']?.toString() ?? '';
    final description = value['description'];
    String? url;
    String? path;
    String? ref;

    if (description is YamlMap) {
      url = description['url']?.toString();
      path = description['path']?.toString();
      ref = description['ref']?.toString();
    } else if (description is String) {
      path = description;
    }

    results.add(
      _LockedPackage(
        name: name,
        version: version,
        source: source,
        url: url,
        path: path,
        ref: ref,
      ),
    );
  }

  return results;
}

String? _packageRoot(_LockedPackage package) {
  if (package.source == 'path' && package.path != null) {
    return p.normalize(p.absolute(package.path!));
  }
  if (package.source != 'hosted') return null;
  final cache = Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache');
  final host = _hostForUrl(package.url);
  return p.normalize(
    p.absolute(
      p.join(cache, 'hosted', host, '${package.name}-${package.version}'),
    ),
  );
}

String _hostForUrl(String? url) {
  if (url == null || url.isEmpty) return 'pub.dev';
  final uri = Uri.tryParse(url);
  if (uri == null) return 'pub.dev';
  if (uri.host.isNotEmpty) return uri.host;
  return 'pub.dev';
}

class _LockedPackage {
  final String name;
  final String version;
  final String source;
  final String? url;
  final String? path;
  final String? ref;

  _LockedPackage({
    required this.name,
    required this.version,
    required this.source,
    required this.url,
    required this.path,
    required this.ref,
  });

  String get sourceId {
    if (source == 'hosted') {
      return 'hosted-${_hostForUrl(url)}';
    }
    if (source == 'path') {
      return 'path-${_sanitizeId(path ?? '')}';
    }
    if (source == 'git') {
      return 'git-${_sanitizeId('${url ?? ''}@${ref ?? ''}')}';
    }
    return _sanitizeId(source);
  }
}

class _FlutterPackage {
  final String name;
  final String path;
  final String version;

  const _FlutterPackage({
    required this.name,
    required this.path,
    required this.version,
  });
}

String _sanitizeId(String raw) {
  if (raw.isEmpty) return 'unknown';
  return raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

void _printUsage() {
  stdout.writeln('Build .throws indexes for external dependencies.');
  stdout.writeln('');
  stdout.writeln(
    'Usage: document_throws_index [--no-packages] [--no-sdk] [--no-flutter]',
  );
  stdout.writeln('       document_throws_index --output=<path> [-q|--quiet]');
}

String _defaultCacheRoot() {
  final cache = Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache');
  return p.join(cache, 'document_throws', 'cache');
}
