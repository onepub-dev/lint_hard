import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:document_throws/src/document_thrown_exceptions_resolver.dart';
import 'package:document_throws/src/throws_cache.dart';
import 'package:document_throws/src/throws_cache_lookup.dart';
import 'package:document_throws/src/unit_provider.dart';
import 'package:test/test.dart';

import 'support/document_thrown_exceptions_helpers.dart';

class _NullUnitProvider implements UnitProvider {
  @override
  CompilationUnit? unitForPath(String path) => null;
}

class _InvalidTypeLookup extends ThrowsCacheLookup {
  _InvalidTypeLookup()
    : super(
        cache: ThrowsCache(Directory.systemTemp.path),
        packageVersions: const {},
        packageSources: const {},
        sdkVersion: 'test',
        sdkRoot: null,
        flutterVersion: null,
      );

  @override
  List<CachedThrownType> lookupWithProvenance(ExecutableElement element) {
    return const [
      CachedThrownType('InvalidType'),
      CachedThrownType('RangeError'),
    ];
  }
}

void main() {
  test('resolver ignores InvalidType from cache', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_invalid_type.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
    final fn = findFunction(resolved.unit.unit, 'invalidTypeThrow');
    final element = fn.declaredFragment!.element;

    final resolver = ThrownTypeResolver(
      _NullUnitProvider(),
      externalLookup: _InvalidTypeLookup(),
    );
    final thrown = resolver.thrownTypesForExecutable(element);

    expect(thrown.any((info) => info.name == 'InvalidType'), isFalse);
    expect(thrown.any((info) => info.name == 'RangeError'), isTrue);
  });
}
