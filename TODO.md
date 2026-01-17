
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

- [] run a performance analysis looking for improvments.
