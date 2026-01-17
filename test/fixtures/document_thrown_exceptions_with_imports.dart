import 'dart:io';
import 'package:path/path.dart';
const sortkeyOption = 'sortkey';

class BadStateException implements Exception {}

void undocumentedTopLevel() {
  throw BadStateException();
}
