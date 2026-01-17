# Throws Cache Format (v1)

This document defines the binary format for per-package `.throws` cache files
used by lint_hard to look up thrown exception types for external libraries.

## Goals
- Fast lookup by executable signature without loading the whole file.
- Single file per package+version (or SDK version).
- Append-only write with the index written at the end of the file.
- Fixed-size index records for fast scanning and predictable I/O.

## File Naming and Location
Per package version:

```
.lint_hard/cache/throws/v1/package/<package>/<version>.throws
```

Per SDK version:

```
.lint_hard/cache/throws/v1/sdk/<sdk_version>.throws
```

`<sdk_version>` should use the full Dart SDK version string.

## Binary Layout
All integers are little-endian.

```
+-----------------------------+
| Header (fixed size)         |
+-----------------------------+
| Data records (variable)     |
+-----------------------------+
| String table (variable)     |
+-----------------------------+
| Index (fixed-size records)  |
+-----------------------------+
| Footer (fixed size)         |
+-----------------------------+
```

### Header (64 bytes)
```
offset size  name
0      8     magic = "LHTHROW\0"
8      4     format_version = 1
12     4     flags (reserved, 0)
16     8     index_offset (absolute file offset)
24     8     index_count (number of index records)
32     8     string_table_offset
40     8     string_table_length
48     8     data_offset (start of data records)
56     8     reserved (0)
```

### Footer (32 bytes)
```
offset size  name
0      8     index_offset (duplicate, for safety)
8      8     index_count
16     8     string_table_offset
24     8     string_table_length
```

The header contains the same offsets as the footer to allow a single read at
either end of the file.

## Index Records (fixed size, 32 bytes)
Index records are sorted by `key_hash` to allow binary search.

```
offset size  name
0      8     key_hash (u64)
8      8     record_offset (absolute file offset)
16     4     record_length (bytes)
20     4     record_key_len (bytes)
24     8     reserved (0)
```

`record_key_len` supports optional verification by comparing the stored key.
If not used, set to 0 and skip key verification.

## Data Records (variable)
Each record encodes one executable signature and its thrown types.

```
offset size  name
0      2     key_length (u16)
2      2     thrown_count (u16)
4      4     reserved (0)
8      N     key_bytes (UTF-8)
8+N    4*M   thrown_type_string_offsets (u32 offsets into string table)
```

`key_length` counts UTF-8 bytes in `key_bytes`. `thrown_count` is the number
of thrown types. Each thrown type is an offset into the string table.

## String Table
A concatenated UTF-8 table of unique strings used by records.

```
offset size  name
0      4     string_count (u32)
4      4*K   string_offsets (u32 offsets into string data)
4+4K   ...   string_data (UTF-8, NUL-terminated)
```

Strings are NUL-terminated for easy scanning. Offsets are relative to the
start of `string_data`.

## Keys
Keys uniquely identify an executable element.

Recommended key format:

```
<library_uri>|<container>#<name>(<param_types>)
```

Examples:

```
package:foo/foo.dart|Foo#bar(int,String)
dart:core|RegExp#RegExp(String,bool,bool,bool,bool)
```

For top-level functions, use `<container>` as `_`:

```
package:foo/foo.dart|_#doThing(String)
```

Parameter types should use the resolved display string without nullability
suffixes stripped (e.g. `String?` is distinct).

## Hashing
Use a stable 64-bit hash of the full key (e.g. xxHash64).
Collisions are handled by verifying the key if `record_key_len > 0`.

## Read Strategy
1) Read header or footer to locate the index.
2) Binary search index by `key_hash`.
3) Read record at `record_offset`.
4) If `record_key_len > 0`, compare key bytes to avoid hash collisions.
5) Resolve thrown type offsets into strings via string table.

## Write Strategy
1) Write header with placeholder offsets.
2) Append data records in any order.
3) Build the string table and append it.
4) Build sorted index records and append them.
5) Write footer.
6) Patch header offsets (or rewrite header once).

## Versioning
Increment `format_version` for any incompatible changes. Keep `flags` for
future feature toggles (e.g. compressed string table).
