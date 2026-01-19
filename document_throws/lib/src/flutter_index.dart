import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

String? flutterRoot(String? sdkRoot) {
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null && envRoot.isNotEmpty) {
    final dir = Directory(envRoot);
    if (dir.existsSync()) return dir.path;
  }
  if (sdkRoot == null) return null;
  final candidates = <String>[
    p.normalize(p.join(sdkRoot, '..', '..')),
    p.normalize(p.join(sdkRoot, '..', '..', '..')),
  ];
  for (final candidate in candidates) {
    final packagesDir = Directory(p.join(candidate, 'packages'));
    final flutterBin = File(p.join(candidate, 'bin', 'flutter'));
    if (packagesDir.existsSync() && flutterBin.existsSync()) {
      return candidate;
    }
  }
  return null;
}

String? flutterVersion(String flutterRootPath) {
  final versionFile = File(p.join(flutterRootPath, 'version'));
  if (versionFile.existsSync()) {
    final value = versionFile.readAsStringSync().trim();
    if (value.isNotEmpty) return value;
  }
  final flutterBin = File(p.join(flutterRootPath, 'bin', 'flutter'));
  if (!flutterBin.existsSync()) return null;
  try {
    final result = Process.runSync(
      flutterBin.path,
      const ['--version', '--machine'],
    );
    if (result.exitCode != 0) return null;
    final output = result.stdout;
    if (output is! String || output.trim().isEmpty) return null;
    final decoded = jsonDecode(output.trim());
    if (decoded is! Map) return null;
    final version = decoded['frameworkVersion']?.toString().trim();
    if (version != null && version.isNotEmpty) return version;
  } catch (_) {
    return null;
  }
  return null;
}

List<FlutterPackage> flutterPackages(
  String flutterRootPath,
  String? flutterSdkVersion,
) {
  if (flutterSdkVersion == null || flutterSdkVersion.isEmpty) {
    return const <FlutterPackage>[];
  }
  final packagesDir = Directory(p.join(flutterRootPath, 'packages'));
  if (!packagesDir.existsSync()) return const <FlutterPackage>[];
  final results = <FlutterPackage>[];
  for (final entity in packagesDir.listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final pubspec = File(p.join(entity.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) continue;
    final info = _readFlutterPackage(pubspec, entity.path, flutterSdkVersion);
    if (info != null) results.add(info);
  }
  return results;
}

FlutterPackage? _readFlutterPackage(
  File pubspec,
  String packagePath,
  String flutterSdkVersion,
) {
  final doc = loadYaml(pubspec.readAsStringSync());
  if (doc is! YamlMap) return null;
  final name = doc['name']?.toString();
  if (name == null || name.isEmpty) return null;
  return FlutterPackage(
    name: name,
    path: packagePath,
    version: flutterSdkVersion,
  );
}

class FlutterPackage {
  final String name;
  final String path;
  final String version;

  const FlutterPackage({
    required this.name,
    required this.path,
    required this.version,
  });
}
