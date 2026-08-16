# 1.1.0
- Fix Dart 3.13 analyzer compatibility
- Add Dart 3.13 lint support

# 1.0.0
- Add dt-fix --remove option to remove @Throwing documentation an annotation
from a project.

# 0.3.0
- Upgraded to the latest version of the dart analyzer.
- Fix analyzer 12 constructor AST usage

# 0.2.1
- improvements to the readme.

# 0.2.0
- Generally clean up around edge cases.
- We no longer look for free form throws sentences in
  doc comments as they are too hard to parse reliably.
- Rename malformed doc lint
- Rename unthrown doc lint
- Add honor-doc-mentions flag to dt-fix
- improved the set of cli examples for the fix tool.
- Preserve indent when updating @Throwing docs
- Document annotation mode

# Unreleased
- added `documented_unthrown_exception` to flag `@Throwing` entries for exceptions that are not thrown.
- improved doc comment parsing and fix output to preserve spacing, indentation-aware wrapping, and remove orphaned provenance lines.
- enhanced doc comment mention handling to limit warnings to inline throw wording.
- added missing cache labels to `throws_index_up_to_date` diagnostics.
- updated CLI tooling to use ArgParser and documented annotation mode.

# 0.1.0
- initial release.
