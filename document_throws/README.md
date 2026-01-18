# document_throws

Document thrown exceptions with @Throws annotations.

## Usage

Add to `analysis_options.yaml`:

```yaml
plugins:
  document_throws:
    diagnostics:
      - document_thrown_exceptions
      - throws_index_up_to_date
```

Add the annotation dependency:

```
dart pub add throws_annotations
```

## CLI

- `document_throws_fix` (alias: `dt-fix`)
- `document_throws_index` (alias: `dt-index`)

## Alternate usage

You can use document_throws without adding it as a dependency. Build the
throws index and run the fix tool periodically. You still need the
annotation package.

Example:

```
dart pub global activate document_throws
dart pub add throws_annotations
dt-index
dt-fix
```
