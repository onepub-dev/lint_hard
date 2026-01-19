
- [] dt-fix and dt-index do not show an error and usage when an invalid
command line arg is passed.  Redo all arg parsing with ArgParser and using the
appropriate addFlag/option methods.

- [] We are still having problems with the lints thing that any type
in side a comment with [] is an exception.

Why are our test picking this up, fix the tests and the code that is
generating the error.

Sample Code:

```
/// Designed to work with [backupFile] to restore
/// a file from backup.
/// The existing file is deleted and restored
/// from the `.bak/<filename>.bak` file created when
/// you called [backupFile].
///
/// Consider using [withFileProtectionAsync] for a more robust solution.
///
/// When the last .bak file is restored, the .bak directory
/// will be deleted. If you don't restore all files (your app crashes)
/// then a .bak directory and files may be left hanging around and you may
/// need to manually restore these files.
/// If the backup file doesn't exists this function throws
/// a [RestoreFileException] unless you pass the [ignoreMissing]
/// flag.
/// @Throwing(ArgumentError)
/// @Throwing(CopyException)
/// @Throwing(DeleteDirException)
/// @Throwing(DeleteException)
/// @Throwing(MoveException)
/// @Throwing(RestoreFileException)
```

Error
```
[{
	"resource": "/home/bsutton/git/dcli/dcli/lib/src/functions/backup.dart",
	"owner": "_generated_diagnostic_collection_name_#26",
	"code": "document_thrown_exceptions_unthrown_doc",
	"severity": 2,
	"message": "Doc comment mentions exception types that are not thrown: backupFile, ignoreMissing, withFileProtectionAsync.\nRemove mentions for exceptions not thrown.",
	"source": "dart",
	"startLineNumber": 66,
	"startColumn": 6,
	"endLineNumber": 66,
	"endColumn": 17,
	"origin": "extHost1"
}]
```

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
