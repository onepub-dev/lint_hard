import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'throws_cache.dart';

class ThrowsCacheLookup {
  final ThrowsCache cache;
  final Map<String, String> packageVersions;
  final Map<String, String> packageSources;
  final String? sdkVersion;
  final String? sdkRoot;
  final String? flutterVersion;

  ThrowsCacheLookup({
    required this.cache,
    required this.packageVersions,
    required this.packageSources,
    required this.sdkVersion,
    required this.sdkRoot,
    required this.flutterVersion,
  });

  List<String> lookup(ExecutableElement element) {
    final uri = element.library.firstFragment.source.uri;
    final scheme = uri.scheme;
    if (scheme == 'package') {
      final package = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      final sourceId = packageSources[package];
      final version =
          sourceId == 'sdk' ? flutterVersion : packageVersions[package];
      if (version == null) return const <String>[];
      final file =
          cache.openPackage(package, version, sourceId: sourceId);
      if (file == null) return const <String>[];
      return file.lookup(_keyForExecutable(element, uri.toString()));
    }
    if (scheme == 'dart') {
      final version = sdkVersion;
      if (version == null) return const <String>[];
      final file = cache.openSdk(version);
      if (file == null) return const <String>[];
      return file.lookup(_keyForExecutable(element, uri.toString()));
    }
    if (scheme == 'file' && sdkRoot != null) {
      final normalized = _sdkLibraryUri(uri, sdkRoot!);
      if (normalized != null) {
        final version = sdkVersion;
        if (version == null) return const <String>[];
        final file = cache.openSdk(version);
        if (file == null) return const <String>[];
        return file.lookup(_keyForExecutable(element, normalized));
      }
    }
    return const <String>[];
  }

  List<CachedThrownType> lookupWithProvenance(ExecutableElement element) {
    final uri = element.library.firstFragment.source.uri;
    final scheme = uri.scheme;
    if (scheme == 'package') {
      final package = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      final sourceId = packageSources[package];
      final version =
          sourceId == 'sdk' ? flutterVersion : packageVersions[package];
      if (version == null) return const <CachedThrownType>[];
      final file =
          cache.openPackage(package, version, sourceId: sourceId);
      if (file == null) return const <CachedThrownType>[];
      return _lookupWithProvenance(file, element, uri.toString());
    }
    if (scheme == 'dart') {
      final version = sdkVersion;
      if (version == null) return const <CachedThrownType>[];
      final file = cache.openSdk(version);
      if (file == null) return const <CachedThrownType>[];
      return _lookupWithProvenance(file, element, uri.toString());
    }
    if (scheme == 'file' && sdkRoot != null) {
      final normalized = _sdkLibraryUri(uri, sdkRoot!);
      if (normalized != null) {
        final version = sdkVersion;
        if (version == null) return const <CachedThrownType>[];
        final file = cache.openSdk(version);
        if (file == null) return const <CachedThrownType>[];
        return _lookupWithProvenance(file, element, normalized);
      }
    }
    return const <CachedThrownType>[];
  }

  List<CachedThrownType> _lookupWithProvenance(
    ThrowsCacheFile file,
    ExecutableElement element,
    String libraryUri,
  ) {
    final key = _keyForExecutable(element, libraryUri);
    final thrown = file.lookup(key);
    if (thrown.isEmpty) return const <CachedThrownType>[];
    final provenance = file.lookupProvenance(key);
    final results = <CachedThrownType>[];
    for (final name in thrown) {
      results.add(
        CachedThrownType(
          name,
          provenance: provenance[name] ?? const <ThrowsProvenance>[],
        ),
      );
    }
    return results;
  }

  MissingThrowsCaches missingCaches() {
    final missingPackages = <String>[];
    for (final entry in packageVersions.entries) {
      final package = entry.key;
      final sourceId = packageSources[package];
      final version =
          sourceId == 'sdk' ? flutterVersion ?? entry.value : entry.value;
      final path = cache.packageCachePath(
        package,
        version,
        sourceId: sourceId,
      );
      if (!File(path).existsSync()) {
        missingPackages.add(package);
      }
    }

    final sdkMissing = sdkVersion == null ||
        !File(cache.sdkCachePath(sdkVersion!)).existsSync();

    return MissingThrowsCaches(
      sdkMissing: sdkMissing,
      missingPackages: missingPackages,
    );
  }

  static ThrowsCacheLookup? forProjectRoot(String rootPath) {
    return forProjectRootWithCache(rootPath, _defaultCacheRoot());
  }

  static ThrowsCacheLookup? forProjectRootWithCache(
    String rootPath,
    String cacheRoot,
  ) {
    final lock = File(p.join(rootPath, 'pubspec.lock'));
    if (!lock.existsSync()) return null;
    final packageVersions = _readPackageVersions(lock);
    final packageSources = _readPackageSources(lock);
    if (packageVersions.isEmpty) return null;
    final cache = ThrowsCache(cacheRoot);
    final sdkVersion = _sdkVersion();
    final sdkRoot = _sdkRootFromExecutable();
    final flutterVersion = _flutterVersion(sdkRoot);
    return ThrowsCacheLookup(
      cache: cache,
      packageVersions: packageVersions,
      packageSources: packageSources,
      sdkVersion: sdkVersion,
      sdkRoot: sdkRoot,
      flutterVersion: flutterVersion,
    );
  }
}

class MissingThrowsCaches {
  final bool sdkMissing;
  final List<String> missingPackages;

  const MissingThrowsCaches({
    required this.sdkMissing,
    required this.missingPackages,
  });

  bool get isEmpty => !sdkMissing && missingPackages.isEmpty;
}

class CachedThrownType {
  final String name;
  final List<ThrowsProvenance> provenance;

  const CachedThrownType(
    this.name, {
    this.provenance = const [],
  });
}

String _keyForExecutable(ExecutableElement element, String libraryUri) {
  if (element is ConstructorElement) {
    final className = element.enclosingElement.name ?? '';
    final ctorElementName = element.name;
    final ctorName = (ctorElementName == null || ctorElementName.isEmpty)
        ? className
        : '$className.$ctorElementName';
    final baseKey = ThrowsCacheKeyBuilder.build(
      libraryUri: libraryUri,
      container: className,
      name: ctorName,
      parameterTypes: _parameterTypes(element),
    );
    final line = _lineNumberForElement(element);
    return line == null ? baseKey : '$baseKey:$line';
  }
  final container = _containerName(element.enclosingElement);
  final name = element.name ?? '';
  final baseKey = ThrowsCacheKeyBuilder.build(
    libraryUri: libraryUri,
    container: container,
    name: name,
    parameterTypes: _parameterTypes(element),
  );
  final line = _lineNumberForElement(element);
  return line == null ? baseKey : '$baseKey:$line';
}

String _containerName(Element? element) {
  if (element is ClassElement) return element.name ?? 'class';
  if (element is MixinElement) return element.name ?? 'mixin';
  if (element is ExtensionElement) return element.name ?? 'extension';
  if (element is InterfaceElement) return element.name ?? 'interface';
  return '_';
}

List<String> _parameterTypes(ExecutableElement element) {
  return element.formalParameters
      .map((parameter) => _typeDisplayName(parameter.type))
      .toList();
}

String _typeDisplayName(DartType type) {
  if (type is VoidType) return 'void';
  return type.getDisplayString();
}

int? _lineNumberForElement(ExecutableElement element) {
  final source = element.library.firstFragment.source;
  final content = source.contents.data;
  final lineInfo = LineInfo.fromContent(content);
  final offset = element.firstFragment.offset;
  return lineInfo.getLocation(offset).lineNumber;
}

Map<String, String> _readPackageVersions(File lockFile) {
  final doc = loadYaml(lockFile.readAsStringSync());
  if (doc is! YamlMap) return const <String, String>{};
  final packages = doc['packages'];
  if (packages is! YamlMap) return const <String, String>{};
  final results = <String, String>{};
  for (final entry in packages.entries) {
    final name = entry.key.toString();
    final value = entry.value;
    if (value is! YamlMap) continue;
    final version = value['version']?.toString();
    if (version == null || version.isEmpty) continue;
    results[name] = version;
  }
  return results;
}

Map<String, String> _readPackageSources(File lockFile) {
  final doc = loadYaml(lockFile.readAsStringSync());
  if (doc is! YamlMap) return const <String, String>{};
  final packages = doc['packages'];
  if (packages is! YamlMap) return const <String, String>{};
  final results = <String, String>{};
  for (final entry in packages.entries) {
    final name = entry.key.toString();
    final value = entry.value;
    if (value is! YamlMap) continue;
    final source = value['source']?.toString() ?? '';
    final description = value['description'];
    String? sourceId;
    if (source == 'hosted') {
      final url = description is YamlMap ? description['url']?.toString() : null;
      sourceId = 'hosted-${_hostForUrl(url)}';
    } else if (source == 'path') {
      final pathValue = description?.toString() ?? '';
      sourceId = 'path-${_sanitizeId(pathValue)}';
    } else if (source == 'git') {
      if (description is YamlMap) {
        final url = description['url']?.toString() ?? '';
        final ref = description['ref']?.toString() ?? '';
        sourceId = 'git-${_sanitizeId('$url@$ref')}';
      }
    } else {
      sourceId = _sanitizeId(source);
    }
    if (sourceId != null && sourceId.isNotEmpty) {
      results[name] = sourceId;
    }
  }
  return results;
}

String _sdkVersion() {
  final full = Platform.version;
  final parts = full.split(' ');
  return parts.isEmpty ? 'unknown' : parts.first;
}

String _defaultCacheRoot() {
  final cache = Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache');
  return p.join(cache, 'lint_hard', 'cache');
}

String? _sdkRootFromExecutable() {
  final exec = Platform.resolvedExecutable;
  if (exec.isEmpty) return null;
  final binDir = File(exec).parent;
  return binDir.parent.path;
}

String? _flutterVersion(String? sdkRoot) {
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  final root = envRoot == null || envRoot.isEmpty
      ? _flutterRootFromSdk(sdkRoot)
      : envRoot;
  if (root == null || root.isEmpty) return null;
  final versionFile = File(p.join(root, 'version'));
  if (versionFile.existsSync()) {
    final value = versionFile.readAsStringSync().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

String? _flutterRootFromSdk(String? sdkRoot) {
  if (sdkRoot == null) return null;
  final candidate = p.normalize(p.join(sdkRoot, '..', '..', '..'));
  final packagesDir = Directory(p.join(candidate, 'packages'));
  final flutterBin = File(p.join(candidate, 'bin', 'flutter'));
  if (packagesDir.existsSync() && flutterBin.existsSync()) {
    return candidate;
  }
  return null;
}

String? _sdkLibraryUri(Uri uri, String sdkRoot) {
  if (uri.scheme != 'file') return null;
  final libRoot = p.normalize(p.join(sdkRoot, 'lib'));
  final filePath = p.normalize(uri.toFilePath());
  if (!p.isWithin(libRoot, filePath)) return null;
  final relative = p.relative(filePath, from: libRoot);
  final relativeParts = p.split(relative);
  final posixRelative = p.posix.joinAll(relativeParts);
  return 'dart:$posixRelative';
}

String _sanitizeId(String raw) {
  if (raw.isEmpty) return 'unknown';
  return raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

String _hostForUrl(String? url) {
  if (url == null || url.isEmpty) return 'pub.dev';
  final uri = Uri.tryParse(url);
  if (uri == null) return 'pub.dev';
  if (uri.host.isNotEmpty) return uri.host;
  return 'pub.dev';
}
