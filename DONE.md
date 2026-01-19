
- [x] can the throws annotation allow the user to add a description for
each throw - i.e a reason is thrown.

- [x] add tests where the fix updates an existing @Throwing annotation to add/remove
a new exception. With and without a ThrowsSpec.

- [x] Add a lint that warns the user if the throws index is out of date
i.e. an new sdk or package version exists for which we don't have an index.

- [x] the lint_hard_index tool should report its version when starting.

- [x] and an exe statement to the pubspec.yaml for each of the binaries.

- [x] Update fixes to use the throws cache when adding @Throwing for external calls.

- [x] Document @Throwing usage in README for document_thrown_exceptions.

- [x] Add a small cache fixture test that reads a real .throws file (not stubbed).

- [x] review the code for additional tests that we should add and add them.

- [x] change the throws annotation to take a single exception and then add
mulitiple @throws to method/function/... as needed. This also gives us a simplier
syntax for providing the reason.  
```
@Throwing(BadState, reason: "xxxx")
```
The reason is optional. 
This still doesn't show throw list in documentation, but after making
a call the linter will warn you about new exceptions that are thrown.

- [x] The lint error should show the list of missing exception types.

- [x] AFter adding a Throwing annotation the method is still show the missing
exception lint.

- [x] there is a question around the source of a throws clause. 
If we document a throws because a called method in an external package
throws (but doesn't document that it throws) the the user may be left
wondering where the source of the throws is. 
Should we augment the throws annotation to indicate 'external' and 
maybe the call that throws it.  Perhaps we only do this if the throws
isn't documented - which means we need to parse doc comments again.
The fact that the exception is documented or not could be added to our index.

- [x] so the downside to an annotation is that the users production code
now has to rely on lint_hard.  Should we have a separate package for the
annotation so dependency is small and introduces no transient dependencies.
I'm also considering moving this whole throws lint into its own package 
as some people wont' what the rest of what lint_hard brings with it.

- [x] what is our objective - to document what exceptions are thrown by
the users own code as well as 3rd party packages and the dart and flutter sdks.
I'm concerned that by using an annotation the vs-code (and other) IDE won't show
the exceptions - particurly for external packges. Do we need an vs-code/andriod studio
extension so that these are show. Can we get the ide teams to support our annotations.

- [x] index tool needs to index the flutter sdk.


- [x] if an exception listed in the @Throwing declaration is from an alised import
then the lint fix commend generates an error as the exception is unkown due to the 
missing alias prefix. 
```

import 'package:lint_hard/throws.dart';
import 'package:yaml/yaml.dart' as y;

/// wrapper for the YamlDocument
/// designed to make it easier to read yaml files.
class MyYaml {
  late y.YamlDocument _document;

  /// read yaml from string
@Throwing([YamlException])
  MyYaml.fromString(String content) {
    _document = _load(content);
  }
  ```
  YamlException needs to be written as y.YamlException.

  - [x] The index format duplicates the offsets in teh footer. However the data_offset isn't duplicated. 
  The Data record describes the thrown_type_string_offest as 4*M without defining M. The same goes for the String Tab (K).

  Provide better examples of how the string table is used.
  Provide an explaination of what a <container> is in the Keys section, 
  don't use RegEx as an example. 


 - [x] move the throws lint and associated tooling into its own package document_throws.
 - [x] the @Throwing annotation should be placed in its own package as its needed for 
 production code not just a dev dependency - is there any advantage to this, 
 we still get dev conflicts.

 - [x] consider change where we store the indices so that a dart pub cache reset
 also resets our indicies - can we safely store index in the existing package
 directory?

 - [x] Do we need to document what a lambda throws? How would we do this.

 - [x] when parsing external packages we should be able to recognize our own
 @Throwing declaration.  The questions is do we trust these or should we still
 do our own inspections?

 - [x] document the use of 'peek definition' in vs-code to see the annotations.

  - [x] When a library is a 'part of' another library the imports have to be
  placed in the part library. Currently we place them in the 'part of' library
  which is causing errors.


- [x] do recreate the indexes if they already exist unless the user passes
the --recreate flag.

- [x] check the flutter sdk indexes are being built

- [x] create test to ensure that we are indexing exceptions in the
flutter sdk that are at least second level call and that we are
annotating code that uses one of those calls.

- [x] I want to add in a command line switch (and analysis_options config)
to switch between using the @Throwing annotation and using a doc comment.
When we use a doc comment we still want to add the same @Throw
syntax as we want the ability to parse a structure throws statement in
a comment.  As such we need to ensure that we are actually parsing
the @throws (unless the dart ast does it for us) statement so that
some variations in formatting are tolerated i.e. split across multiple lines.
I want the doc code method to be the default with a switch to use the annotation.

- [x] create a separate annotations package that can be added as a dependency
when a user uses the @Throwing annotation to avoid having to depend (for production)
on the full document_throws package with its transient dependency.

- [x] document how a package maintianer can use this package to add throws
statements (in doc comments) as part of their release pipeline without
depending on our package.

- [x] I ran fix with --origin and the fix without origin. 
The second run just added an additional throws without removing the orgin versions:

- [x] rename the throws_annotation package to document_throws_annotation.
```
/// 
/// @Throwing(ArgumentError, call: 'args|addFlag', origin: 'args|_addOption')
/// @Throwing(ArgumentError, call: 'args|addOption', origin: 'args|_addOption')
/// @Throwing(
///   ArgumentError,
///   call: 'args|addMultiOption',
///   origin: 'args|_addOption',
/// )
/// @Throwing(ArgumentError)
```

Add tests for this.


- [x] The Throws annotation conflicts with the test packages 'Throws' class.   It would be good to find a name
that is still indicative of what the annotation does
but which doesn't conflict with the test package.
Rename the annotation to @Throwing

- [x] create a detail set of unit tests for parsing the doc comments for @Throwing
including dealing with providing good errors via lint output.

- [x] trying to remove orgins with the fix command is still failing:

```

const fieldDelimiterOption = 'field-delimiter';
const lineDelimiterOption = 'line-delimiter';
const sortkeyOption = 'sortkey';
const outputOption = 'output';

/// @Throwing(ArgumentError)

void main(List<String> args) {
  dsort(args);
}

/// ArgumentError,
/// call: 'args|addMultiOption',
/// origin: 'args|_addOption',
/// )
/// @Throwing(ArgumentError)
```

- [x] should there be a new line between the doc command and the method.
Implement whatever is the dart standard.

```
/// @Throwing(ArgumentError)

void main(List<String> args) {
  dsort(args);
}
```

- [x] If a method/fuction/... doc comment mentions an Exception
then don't add a doc comment for that exception as we will assume 
the exception is already throw. This should also suppress the lint
but if the exception is mentioned in the doc comments and the exception is
not throw then warn with a lint.

- [x] Create a section need the end of the readme that discussion why we
chose doccomments over annotations and why we chose Throwing over Throws
plus any other key decisions that affect the user experience.

- [x] ensure that we are indexing transient dependencies and the
correct version of those dependencies. 
We probably need to be reading the pubspec.lock file in order to do this.

- [x] I'm concerned about the indexing of the flutter sdk. I'm seeing
a lot of unknowns. I'm concerned that this means we aren't finding the
index when the lint is running.  Given the number of index
files do we need an index for the index?
Indexing Flutter SDK unknown
Indexing Flutter package flutter_goldens unknown (1/9)
Skipping Flutter package flutter_goldens unknown (index exists).
Indexing Flutter package flutter unknown (2/9)
Skipping Flutter package flutter unknown (index exists).
Indexing Flutter package flutter_test unknown (3/9)
Skipping Flutter package flutter_test unknown (index exists).
Indexing Flutter package flutter_tools unknown (4/9)
Skipping Flutter package flutter_tools unknown (index exists).
Indexing Flutter package integration_test unknown (5/9)
Skipping Flutter package integration_test unknown (index exists).
Indexing Flutter package fuchsia_remote_debug_protocol unknown (6/9)
Skipping Flutter package fuchsia_remote_debug_protocol unknown (index exists).
Indexing Flutter package flutter_localizations unknown (7/9)
Skipping Flutter package flutter_localizations unknown (index exists).
Indexing Flutter package flutter_web_plugins unknown (8/9)
Skipping Flutter package flutter_web_plugins unknown (index exists).
Indexing Flutter package flutter_driver unknown (9/9)
Skipping Flutter package flutter_driver unknown (index exists).

- [x] the indexer appears to output two messages when skipping an index
Indexing Flutter package flutter_driver unknown (9/9)
Skipping Flutter package flutter_driver unknown (index exists).

Instead it should only output the skipping message.

- [x] the indexer should provide a summary - n packages indexed, m packages skipped. 

- [x] in case the user switches between doc comments and annotations
then we should remove the other type, where it is safe to do so.

- [x] method not annotated when core.restoreFile throws exception.
In the dcli project ~/git/dcli/dcli and ~/git/dcli/dcli_core the
restoreFile method in lib/src/functions/backup.dart calls a method
of the same name in the dcli_core package. The problem is that the 
throws statements are not being added by the fix app.

```dart
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
void restoreFile(String pathToFile, {bool ignoreMissing = false}) =>
    core.restoreFile(pathToFile, ignoreMissing: ignoreMissing);
```    

- [x] the indexer is reporting:

```
Unable to determine Flutter SDK version; skipping Flutter index.
```

we need to determine why. Perhaps we need to determine a more reliable way
of determine the flutter verions.

```
flutter doctor
Doctor summary (to see all details, run flutter doctor -v):
[✓] Flutter (Channel beta, 3.41.0-0.0.pre, on Ubuntu 25.10 6.11.0-26-generic, locale en_AU.UTF-8)
[✓] Android toolchain - develop for Android devices (Android SDK version 36.0.0)
[✓] Chrome - develop for the web
[✓] Linux toolchain - develop for Linux desktop
[✓] Connected device (2 available)
[✓] Network resources

• No issues found!
```

- [x] lint hard should depend on document_throws and enable the dt plugin with
instructions on how to disable any of our custom lints.

- [x] optimise the code and improve the code structure.

