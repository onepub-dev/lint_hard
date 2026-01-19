# External @Throwing Annotations (Design)

## Summary
When indexing external packages, we can either trust existing `@Throwing`
annotations or compute thrown exceptions from the AST.

## Decision
Continue to compute thrown exceptions from the AST. If a package already
uses `@Throwing`, those annotations should match the implementation and the
computed results will stay consistent. This avoids trusting stale
documentation and keeps indexing rules uniform.

## Future option
Allow a configuration flag to trust annotations when present and skip
body analysis for those executables, as a performance optimization.
