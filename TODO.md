
- [x] can the throws annotation allow the user to add a description for
each throw - i.e a reason is thrown.

- [x] add tests where the fix updates an existing @Throws annotation to add/remove
a new exception. With and without a ThrowsSpec.

- [x] Add a lint that warns the user if the throws index is out of date
i.e. an new sdk or package version exists for which we don't have an index.

- [x] the lint_hard_index tool should report its version when starting.

- [x] and an exe statement to the pubspec.yaml for each of the binaries.

- [x] Update fixes to use the throws cache when adding @Throws for external calls.

- [x] Document @Throws usage in README for document_thrown_exceptions.

- [x] Add a small cache fixture test that reads a real .throws file (not stubbed).

- [x] review the code for additional tests that we should add and add them.

- [x] change the throws annotation to take a single exception and then add
mulitiple @throws to method/function/... as needed. This also gives us a simplier
syntax for providing the reason.  
```
@Throws(BadState, reason: "xxxx")
```
The reason is optional. 
This still doesn't show throw list in documentation, but after making
a call the linter will warn you about new exceptions that are thrown.

- [x] The lint error should show the list of missing exception types.

- [x] AFter adding a Throws annotation the method is still show the missing
exception lint.

- [] there is a question around the source of a throws clause. 
If we document a throws because a called method in an external package
throws (but doesn't document that it throws) the the user may be left
wondering where the source of the throws is. 
Should we augment the throws annotation to indicate 'external' and 
maybe the call that throws it.  Perhaps we only do this if the throws
isn't documented - which means we need to parse doc comments again.
The fact that the exception is documented or not could be added to our index.

- [] so the downside to an annotation is that the users production code
now has to rely on lint_hard.  Should we have a separate package for the
annotation so dependency is small and introduces no transient dependencies.
I'm also considering moving this whole throws lint into its own package 
as some people wont' what the rest of what lint_hard brings with it.

- [] what is our objective - to document what exceptions are thrown by
the users own code as well as 3rd party packages and the dart and flutter sdks.
I'm concerned that by using an annotation the vs-code (and other) IDE won't show
the exceptions - particurly for external packges. Do we need an vs-code/andriod studio
extension so that these are show. Can we get the ide teams to support our annotations.

- [x] index tool needs to index the flutter sdk.


- [] if an exception listed in the @Throws declaration is from an alised import
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
@Throws([YamlException])
  MyYaml.fromString(String content) {
    _document = _load(content);
  }
  ```
  YamlException needs to be written as y.YamlException.

 - [] move the throws lint and associated tooling into its own package document_throws.
 the @Throws annotation should be placed in its own package as its needed for 
 production code not just a dev dependency - is there any advantage to this, 
 we still get dev conflicts.

 - [] consider change where we store the indices so that a dart pub cache reset
 also resets our indicies - can we safely store index in the existing package
 directory?

 - [] document the use of 'peek definition' in vs-code to see the annotations.

  - [] When a library is a 'part of' another library the imports have to be
  placed in the part library. Currently we place them in the 'part of' library
  which is causing errors.

- [] optimise the code and improve the code structure.

- [] run a performance analysis looking for improvments.
