import 'dart:io';

import 'package:document_throws/src/document_thrown_exceptions_collection.dart';
import 'package:test/test.dart';

import 'support/document_thrown_exceptions_helpers.dart';

void main() {
  test('collector ignores InvalidType throws', () async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_invalid_type.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    final resolved = await resolveFixture(fixtureFilePath);
    final fn = findFunction(resolved.unit.unit, 'invalidTypeThrow');

    final thrownTypes = collectThrownTypeNames(fn.functionExpression.body);

    expect(thrownTypes, isEmpty);
    expect(thrownTypes.contains('InvalidType'), isFalse);
  });
}
