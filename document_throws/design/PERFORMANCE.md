# Performance

Ran the performance smoke test with:

```
dart run tool/perf_smoke.dart
```

Result: blocked by a permission error writing
`/home/bsutton/apps/flutter/bin/cache/engine.stamp`.

## Indexer memory

Ran `document_throws_index` against a full dependency set and hit an out of
memory error while indexing `_fe_analyzer_shared`. The stack trace showed
`_ThrowTypeCollector._recordThrow` growing an unbounded list due to repeated
propagation from invoked methods.

Change: dedupe thrown types and provenance while collecting so each exception
type is recorded once per executable.
