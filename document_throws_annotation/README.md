# document_throws_annotation

Provides `@Throwing` annotations for documenting thrown exceptions.

Use this package when you enable annotation mode in `document_throws`.

Example:

```dart
import 'package:document_throws_annotation/document_throws_annotation.dart';

@Throwing(FormatException)
void parse(String value) {
  throw FormatException('bad');
}
```
