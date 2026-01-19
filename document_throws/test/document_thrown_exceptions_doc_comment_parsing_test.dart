import 'dart:io';

import 'package:document_throws/src/throwing_doc_parser.dart';
import 'package:test/test.dart';

import 'support/document_thrown_exceptions_helpers.dart';

void main() {
  late ResolvedFixture fixture;

  setUpAll(() async {
    final fixturePath =
        'test/fixtures/document_thrown_exceptions_doc_comment_parsing.dart';
    final fixtureFilePath = File(fixturePath).absolute.path;
    fixture = await resolveFixture(fixtureFilePath);
  });

  test('parses single-line @Throwing doc comments', () {
    final method = findMethod(fixture.unit.unit, 'singleLine');
    final result = parseThrowingDocComment(method.documentationComment);

    expect(result.typeNames, equals(['FooException']));
    expect(result.errors, isEmpty);
  });

  test('parses block doc comments with @Throwing', () {
    final method = findMethod(fixture.unit.unit, 'blockDoc');
    final result = parseThrowingDocComment(method.documentationComment);

    expect(result.typeNames, equals(['BarException']));
    expect(result.errors, isEmpty);
  });

  test('parses multi-line @Throwing args', () {
    final method = findMethod(fixture.unit.unit, 'multiLine');
    final result = parseThrowingDocComment(method.documentationComment);

    expect(result.typeNames, equals(['BazException']));
    expect(result.errors, isEmpty);
  });

  test('captures generic types in @Throwing', () {
    final method = findMethod(fixture.unit.unit, 'genericType');
    final result = parseThrowingDocComment(method.documentationComment);

    expect(result.typeNames, equals(['GenericException<String>']));
    expect(result.errors, isEmpty);
  });

  test('parses multiple @Throwing tags', () {
    final method = findMethod(fixture.unit.unit, 'multipleTags');
    final result = parseThrowingDocComment(method.documentationComment);

    expect(result.typeNames, equals(['FooException', 'BarException']));
    expect(result.errors, isEmpty);
  });

  test('reports missing type arguments in @Throwing', () {
    final method = findMethod(fixture.unit.unit, 'missingArg');
    final result = parseThrowingDocComment(method.documentationComment);

    expect(result.typeNames, isEmpty);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.message, contains('Missing exception type'));
  });

  test('reports missing closing paren', () {
    final method = findMethod(fixture.unit.unit, 'missingParen');
    final result = parseThrowingDocComment(method.documentationComment);

    expect(result.typeNames, isEmpty);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.message, contains('Missing ")"'));
  });

  test('reports missing open paren', () {
    final method = findMethod(fixture.unit.unit, 'missingOpenParen');
    final result = parseThrowingDocComment(method.documentationComment);

    expect(result.typeNames, isEmpty);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.message, contains('Missing "("'));
  });
}
