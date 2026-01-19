# Throws Cache Storage (Design)

The throws index is stored under the pub cache:

```
<PUB_CACHE>/document_throws/cache/throws/v1/...
```

This location is cleared when the pub cache is reset, so the index does not
outlive the packages it describes. The cache root is kept separate from
package directories to avoid mutating cached packages and to keep the index
layout consistent across hosted, git, and path dependencies.

Alternative considered:
store indexes inside each package directory under the pub cache. This was
rejected to avoid writing into cached packages and to keep cache lookup and
cleanup consistent across sources.
