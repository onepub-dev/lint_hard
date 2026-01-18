import 'package:throws_annotations/throws_annotations.dart';

@Throws(FormatException, call: 'dart:core|RegExp.new', origin: 'dart:core|RegExp')
void usesRegExp() {
  RegExp('[');
}
