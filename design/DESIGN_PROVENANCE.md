# Throws Provenance (Design)

This document describes a debug-mode provenance extension for the throws index
and how the fix tool should surface provenance in `@Throws` annotations.

## Goals
- Always record provenance data for thrown exceptions in the throws cache.
- Surface provenance in `@Throws` only when requested by the fix tool.
- Distinguish between immediate call-site source and ultimate origin.

## Index Format (v1 with a flag)
- Use a v1 header flag to indicate provenance data is present.
- No format version bump; this is still v1.

Proposed header flags:
- `0x01`: provenance enabled.

## Provenance Storage
Per thrown type entry, store zero or more provenance records.

Suggested provenance fields:
- `call`: the immediate call-site origin (callee signature)
- `origin`: the ultimate source of the throw (callee signature)

Provenance is always stored during indexing.

The 'call' site uses the full executable key so it is unambiguous.

The origin is only output when it differs from the call.

## Provenance Keys
Use the same executable key format used for thrown entries:

```
<library_uri>|<container>#<name>(<param_types>)
```

Examples:

```
package:foo/bar.dart|Foo#baz(int,String)
dart:io|File#writeAsString(String,Encoding?)
```

For external packages and SDK entries, append a 1-based line number:

```
package:foo/bar.dart|Foo#baz(int,String):123
```

Line numbers are not included for local (project) provenance.

## Provenance Rules
- Local project code is not indexed. Provenance is still recorded when a local
  call ultimately throws via an external dependency; `call` identifies the
  immediate callee (which may be local), and `origin` identifies the external
  source when it differs from `call`.
- Direct throws in the current method body:
  no provenance entry (clean annotation output for local throws).
- Throws propagated from external packages or SDK:
  `call` points to the immediate external callee key.
  `origin` is only present when the ultimate source differs from `call`.
  For external entries, keys include a line number suffix.

## Index Builder Changes
- Always collect provenance for each thrown type while building the index.
- Add provenance records to the data section using the v1 provenance flag.

## Annotation Shape
No enum. Use additional optional args in `@Throws`:

```dart
@Throws(
  BadStateException,
  call: 'package:foo/bar.dart|Foo#baz(int)',
  origin: 'package:foo/bar.dart|Foo#baz(int)',
)
```

## Fix Tool Behavior
- `lint_hard_fix` uses `--source` to include provenance fields.
- Without `--source`, annotations are written without provenance.
- When `--source` is used and provenance exists, the fix updates annotations
  to include `call` and `origin`.
  It prints a reminder that provenance can be removed by re-running the fix
  without `--source`.

## Removal Path
To remove provenance from code:
1. Remove existing `@Throws` annotations.
2. Re-run the fix tool without `--source`.

## Open Questions
- Provenance string size limits and compression.
