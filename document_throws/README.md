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

## CLI

- `document_throws_fix` (alias: `dt-fix`)
- `document_throws_index` (alias: `dt-index`)
