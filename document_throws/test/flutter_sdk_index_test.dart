import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:document_throws/src/document_thrown_exceptions.dart';
import 'package:document_throws/src/document_thrown_exceptions_fix_utils.dart';
import 'package:document_throws/src/throws_cache.dart';
import 'package:document_throws/src/throws_cache_indexer.dart';
import 'package:document_throws/src/throws_cache_lookup.dart';
import 'package:document_throws/src/throws_cache_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('indexes flutter sdk calls and annotates using cache', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('document_throws_flutter_index_');
    try {
      final flutterRoot = p.join(tempDir.path, 'flutter');
      final flutterPkgRoot = p.join(flutterRoot, 'packages', 'flutter_pkg');
      final flutterLib = p.join(flutterPkgRoot, 'lib');
      Directory(flutterLib).createSync(recursive: true);
      File(p.join(flutterPkgRoot, 'pubspec.yaml')).writeAsStringSync(
        'name: flutter_pkg\n',
      );
      File(p.join(flutterLib, 'flutter_pkg.dart')).writeAsStringSync('''
class FlutterApi {
  void level2() {
    throw FormatException('bad');
  }

  void level1() {
    level2();
  }
}

void level0() {
  FlutterApi().level1();
}
''');
      _writePackageConfig(
        flutterPkgRoot,
        packages: {
          'flutter_pkg': flutterPkgRoot,
        },
      );

      final flutterFile = p.join(flutterLib, 'flutter_pkg.dart');
      final flutterCollection = AnalysisContextCollection(
        includedPaths: [flutterFile],
      );
      final flutterSession =
          flutterCollection.contextFor(flutterFile).currentSession;
      final flutterLibrary = await flutterSession.getResolvedLibrary(
        flutterFile,
      );
      if (flutterLibrary is! ResolvedLibraryResult) {
        throw StateError('Failed to resolve flutter package');
      }
      final entries = buildThrowsIndex(
        flutterLibrary,
        libraryUri: 'package:flutter_pkg/flutter_pkg.dart',
      );
      final level0Key = entries.keys.firstWhere(
        (key) => key.contains('#level0('),
      );
      expect(
        entries[level0Key]?.thrown.toSet(),
        equals({'FormatException'}),
      );

      final cacheRoot = p.join(tempDir.path, 'cache');
      final cacheFile = File(
        p.join(
          cacheRoot,
          'throws',
          'v1',
          'package',
          'flutter_pkg',
          'sdk',
          '3.0.0.throws',
        ),
      );
      ThrowsCacheWriter.writeFileSync(cacheFile, entries);

      final appRoot = p.join(tempDir.path, 'app');
      final appLib = p.join(appRoot, 'lib');
      Directory(appLib).createSync(recursive: true);
      File(p.join(appRoot, 'pubspec.yaml')).writeAsStringSync('name: app\n');
      File(p.join(appLib, 'app.dart')).writeAsStringSync('''
import 'package:flutter_pkg/flutter_pkg.dart';

void usesFlutter() {
  level0();
}
''');
      _writePackageConfig(
        appRoot,
        packages: {
          'app': appRoot,
          'flutter_pkg': flutterPkgRoot,
        },
      );

      final appFile = p.join(appLib, 'app.dart');
      final appCollection = AnalysisContextCollection(
        includedPaths: [appRoot],
      );
      final appSession = appCollection.contextFor(appFile).currentSession;
      final appUnit = await appSession.getResolvedUnit(appFile);
      final appLibrary = await appSession.getResolvedLibrary(appFile);
      if (appUnit is! ResolvedUnitResult ||
          appLibrary is! ResolvedLibraryResult) {
        throw StateError('Failed to resolve app');
      }
      final usesFlutter = appUnit.unit.declarations
          .whereType<FunctionDeclaration>()
          .firstWhere((node) => node.name.lexeme == 'usesFlutter');
      final body = usesFlutter.functionExpression.body;
      final block = body is BlockFunctionBody ? body.block : null;
      final invocation = block?.statements
          .whereType<ExpressionStatement>()
          .map((statement) => statement.expression)
          .whereType<MethodInvocation>()
          .first;
      if (invocation == null) {
        throw StateError('No invocation found in usesFlutter');
      }
      final invokedElement = invocation.methodName.element;
      expect(invokedElement, isNotNull);
      final invokedLibrary = invokedElement!.library;
      expect(invokedLibrary, isNotNull);
      expect(invokedLibrary!.firstFragment.source.uri.scheme, 'package');

      final invocationElement = invokedElement as ExecutableElement;
      final lookupKey = _keyForExecutable(invocationElement);
      expect(entries.keys, contains(lookupKey));
      final method = appUnit.unit.declarations
          .whereType<FunctionDeclaration>()
          .firstWhere((node) => node.name.lexeme == 'usesFlutter');

      final lookup = ThrowsCacheLookup(
        cache: ThrowsCache(cacheRoot),
        packageVersions: const {'flutter_pkg': '0.0.0'},
        packageSources: const {'flutter_pkg': 'sdk'},
        sdkVersion: null,
        sdkRoot: null,
        flutterVersion: '3.0.0',
      );
      final missing = missingThrownTypeInfos(
        method.functionExpression.body,
        method.metadata,
        unitsByPath: unitsByPathFromResolvedUnits(appLibrary.units),
        externalLookup: lookup,
      );

      expect(missing.map((info) => info.name).toSet(), {'FormatException'});
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

String _keyForExecutable(ExecutableElement element) {
  final libraryUri = element.library.firstFragment.source.uri.toString();
  final container = element.enclosingElement is ClassElement
      ? element.enclosingElement!.name ?? 'class'
      : element.enclosingElement is MixinElement
          ? element.enclosingElement!.name ?? 'mixin'
          : element.enclosingElement is ExtensionElement
              ? element.enclosingElement!.name ?? 'extension'
              : element.enclosingElement is InterfaceElement
                  ? element.enclosingElement!.name ?? 'interface'
                  : '_';
  final name = element.name ?? '';
  final baseKey = ThrowsCacheKeyBuilder.build(
    libraryUri: libraryUri,
    container: container,
    name: name,
    parameterTypes: element.formalParameters
        .map((parameter) => parameter.type.getDisplayString())
        .toList(),
  );
  final source = element.library.firstFragment.source;
  final lineInfo = LineInfo.fromContent(source.contents.data);
  final line = lineInfo.getLocation(element.firstFragment.offset).lineNumber;
  return '$baseKey:$line';
}

void _writePackageConfig(
  String packageRoot, {
  required Map<String, String> packages,
}) {
  final toolDir = Directory(p.join(packageRoot, '.dart_tool'))
    ..createSync(recursive: true);
  final configFile = File(p.join(toolDir.path, 'package_config.json'));
  final entries = <Map<String, Object?>>[];
  for (final entry in packages.entries) {
    entries.add({
      'name': entry.key,
      'rootUri': p.toUri(entry.value).toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.7',
    });
  }
  configFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'configVersion': 2,
      'packages': entries,
    }),
  );
}
