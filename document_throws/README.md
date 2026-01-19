# document_throws

## Overview

Dart's idomatic error handling is via unchecked exceptions and leaves
it to the developer to document the set of exceptions that a method throws.

The current recommended way to document exceptions is to have a paragraph in the DartDoc starting with the word "Throws" and linking to the exceptions being thrown.

The problem with this manual approach is that developers often fail to document
the exceptions (even the SDK fails to document many exceptions).

As a developer this often leaves us having to examine the source code
of third part packages and even the SDK to determine what exceptions we need
to be handle.

The problem gets worse when you realise that to get an exhaustive list
of exceptions, it not just the immediately called function that needs to be
examined but every function that it calls.

The document_throws package attempts to address this issue by exhaustively automating
the documentation of exceptions.

The document_throws package implements:
 1. a lint to inform you when a method or function has not declared
 all exceptions: `document_thrown_exceptions`
 2. a lint to inform you when an exception which is documented isn't acutally
 thrown: `document_thrown_exceptions_unthrown_doc`
 3. a lint if the @Throwing documentation is malformed: `document_thrown_exceptions_malformed_doc`
 4. a lint that informs you if the required indexes don't exist: `throws_index_up_to_date`

### Exhaustive list of exceptions
By 'exhaustively' we mean that document_throws examines not just the immediate
called function but every function in the calls stack, including third
party packages and the Dart and Flutter SDKs.

The document_throws packages is able to do this (performantly)  by building an
index for each dependency including the Dart and Flutter Sdk.

The document_throws package currently supports two forms of documentation
for exceptions:
 1. A structured doc comment.
 2. An annotation

 By default the code outputs a structured doc comment. 

 The reason for this default is that it makes the list of exceptions that
 a method throws, visible through the IDE hover (when you hover of a function call site).

### Structured doc comment.
The structured doc comment has two forms:
  1. Basic @Throwing statement
  2. Extended @Throwing statement that documents the origin of the exception.

  The Extended version is mainly used to debug the document_throws package
  but can provide useful information.
  
  The basic form does not confirm to Darts recommend documentation format due
  to the need to be able to update the list of exceptions thrown. 
  Using a structured syntax allows document_throws the extract the existing 
  list and update it should the list of exceptions change.

  The document_throws package tries to honour existing documenation. If the functions
  doc comment  contains 'Throws' we assume that any [types] noted in the doc comment
  constitute documentation for that Type being thrown and we will not
  added an addtional @Throws for those types.

#### Basic form
The basic form of the doc comment take the form:

```
/// @Throwing(ArgumentError)
/// @Throwing(InvalidType)
```


#### Extended form

The extended form of the doc comment takes the form:
```
/// @Throwing(
///  ArgumentError,
///  call: 'matcher|expect',
///  origin: 'matcher|_wrapArgs',
/// )
/// @Throwing(InvalidType, call: 'matcher|expect', origin: 'matcher|fail')
```

### Annotations
The annotation form is identical to the dart doc form except that it
is a Dart Annotation.

To use the annotation form you need to add document_throws_annotation to
your dependency list. This a tiny package with no transient dependencies, it only
declares the annotation.

```
dart pub add document_throws_annotation
```

To enable the alternate annotation method:

Add the annotation dependency, then configure document_throws to emit
annotations instead of doc comments. After changing the setting, run the
fix tool so existing docs are rewritten.

```
dart pub add document_throws_annotation
```

```yaml
document_throws:
  documentation_style: annotation
```

```
dt-index
dt-fix --annotation
```

### CLI tooling.
The document_throws package ships with two CLI tools
1. the indexer
2. the bulk fix tool




## Installing document_throws

```
dart pub add document_throws
```

If you are using the (non-default) annotation form then you also
need to add: 

```
dart pub add document_throws_annotation
```

## Usage
To enable 

Add to `analysis_options.yaml`:

```yaml
plugins:
  document_throws:
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

## CI/CD integration for maintainers

Run the indexer and fix tool in CI to keep `@Throwing` doc comments aligned
with the latest code before cutting a release. Doc comment mode does not
require a package dependency, so the CI job can use the global tool without
changing `pubspec.yaml`.

Example:

```
dart pub global activate document_throws
dt-index
dt-fix lib/**/*.dart
```

If you want the pipeline to fail when documentation is out of date, check for
modified files after running the fix tool and exit non-zero when changes are
present.

### GitHub Actions example

```yaml
name: document-throws

on:
  push:
    branches: [main]
  pull_request:

jobs:
  document-throws:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - name: Install document_throws
        run: dart pub global activate document_throws
      - name: Update @Throwing docs
        run: |
          dt-index
          dt-fix lib/**/*.dart
      - name: Fail if changes were needed
        run: |
          if ! git diff --quiet; then
            echo "Run dt-index and dt-fix locally to update @Throwing docs."
            git --no-pager diff
            exit 1
          fi
```

### GitLab CI example

```yaml
document_throws:
  image: dart:stable
  stage: test
  script:
    - dart pub global activate document_throws
    - dt-index
    - dt-fix lib/**/*.dart
    - |
      if ! git diff --quiet; then
        echo "Run dt-index and dt-fix locally to update @Throwing docs."
        git --no-pager diff
        exit 1
      fi
```

## Design choices

Doc comments are the default because they show up in editor hovers and API
documentation without additional tooling. Annotations remain available for teams
that prefer structured metadata in code and are already depending on an
annotation package.

The annotation is named `@Throwing` to avoid clashes with `Throws` in the test
package while still describing its intent.
