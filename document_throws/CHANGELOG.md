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
