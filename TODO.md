
- [] We are getting line lengths that are exceeding 80 chars

```
  /// Path to the directory where users can store their own custom templates
  /// @Throwing(ArgumentError, call: 'path|join', origin: 'path|_validateArgList')
  String get pathToTemplateProjectCustom =>
      p.join(pathToDCli, templateDir, 'project', 'custom');
```      
- [] on the main methods of every test I'm getting what appears to be an incorrect
warning - or incorrect throws staments.

```


import 'package:dcli/dcli.dart';
import 'package:posix/posix.dart';
import 'package:test/test.dart';

/// @Throwing(
///  ArgumentError,
///  call: 'matcher|expect',
///  origin: 'matcher|_wrapArgs',
/// )
/// @Throwing(InvalidType, call: 'matcher|expect', origin: 'matcher|fail')
void main() {
  /// This test need to be run under sudo
  test(
    'isPrivligedUser',
    () {
      // Settings().setVerbose(enabled: true);
      expect(Shell.current.isPrivilegedUser, isTrue);
      Shell.current.releasePrivileges();
      expect(Shell.current.isPrivilegedUser, isFalse);
      Shell.current.restorePrivileges();
      expect(Shell.current.isPrivilegedUser, isTrue);
    },
    skip: !Shell.current.isPrivilegedUser,
    tags: [
      'privileged',
    ],
  );


```

[{
	"resource": "/home/bsutton/git/dcli/dcli/test/privileged_test.dart",
	"owner": "_generated_diagnostic_collection_name_#26",
	"code": "document_thrown_exceptions_unthrown_doc",
	"severity": 2,
	"message": "Doc comment mentions exception types that are not thrown: ArgumentError, InvalidType.\nRemove mentions for exceptions not thrown.",
	"source": "dart",
	"startLineNumber": 14,
	"startColumn": 6,
	"endLineNumber": 14,
	"endColumn": 10,
	"origin": "extHost1"
}]
