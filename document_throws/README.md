# document_throws

Document thrown exceptions with @Throwing tags in doc comments (default), or
@Throwing annotations when configured.

## Usage

Add to `analysis_options.yaml`:

```yaml
plugins:
  document_throws:
    diagnostics:
      - document_thrown_exceptions
      - throws_index_up_to_date
```

Doc comment example:

```dart
/// @Throwing(FormatException)
void parse() {
  throw FormatException('bad');
}
```

Annotation example (optional):

```dart
import 'package:document_throws_annotation/document_throws_annotation.dart';

@Throwing(FormatException)
void parse() {
  throw FormatException('bad');
}
```

Add the annotation dependency only when using annotation mode:

```
dart pub add document_throws_annotation
```

Configure the documentation style (optional):

```yaml
document_throws:
  documentation_style: doc_comment # or annotation
```

## CLI

- `document_throws_fix` (alias: `dt-fix`)
- `document_throws_index` (alias: `dt-index`)

`document_throws_fix` defaults to doc comments and accepts `--annotation` or
`--doc-comment` to override.

## Alternate usage

You can use document_throws without adding it as a dependency. Build the
throws index and run the fix tool periodically. If you use annotation mode,
add the annotation package.

Example:

```
dart pub global activate document_throws
dt-index
dt-fix
```

## Release pipeline

Package maintainers can run the indexer and fix tool in CI to update
`@Throwing` doc comments before release. Doc comment mode does not require a
package dependency.

Example:

```
dart pub global activate document_throws
dt-index
dt-fix lib/**/*.dart
```
