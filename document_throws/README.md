# document_throws

## Overview

Dart's idiomatic error handling is via unchecked exceptions and leaves
it to the developer to document the set of exceptions that a method throws.

The current recommended way to document exceptions is to have a paragraph in the DartDoc starting with the word "Throws" and linking to the exceptions being thrown.

The problem with this manual approach is that developers often fail to document
the exceptions (even the SDK fails to document many exceptions).

As a developer this often leaves us having to examine the source code
of third-party packages and even the SDK to determine what exceptions we need
to be handled.

The problem gets worse when you realise that to get an exhaustive list
of exceptions, it is not just the immediately called function that needs to be
examined but every function that it calls.

The document_throws package attempts to address this issue by exhaustively automating
the documentation of exceptions.

The document_throws package implements:
 1. a lint to inform you when a method or function has not declared
 all exceptions: `document_thrown_exceptions`
 2. a lint to inform you when an exception which is documented isn't actually
 thrown: `document_thrown_exceptions_unthrown_doc`
 3. a lint if the @Throwing documentation is malformed: `document_thrown_exceptions_malformed_doc`
 4. a lint that informs you if the required indexes don't exist: `throws_index_up_to_date`

The `document_throws` package treats Error subclasses the same as Exception because
public APIs often throw ArgumentError, StateError, or RangeError and those
are still useful to document.

### Exhaustive list of exceptions
By 'exhaustively' we mean that document_throws examines not just the immediate
called function but every function in the call stack, including third
party packages and the Dart and Flutter SDKs.

The document_throws package is able to do this (performantly) by building an
index for each dependency including the Dart and Flutter SDK.

The document_throws package currently supports two forms of documentation
for exceptions:
 1. A structured doc comment.
 2. An annotation

 By default the code outputs a structured doc comment. 

 The reason for this default is that it makes the list of exceptions that
 a method throws, visible through the IDE hover (when you hover over a function call site).

### Structured doc comment.
The structured doc comment has two forms:
  1. Basic @Throwing statement
  2. Extended @Throwing statement that documents the origin of the exception.

  The Extended version is mainly used to debug the document_throws package
  but can provide useful information.
  
  The basic form does not conform to Dart's recommended documentation format due
  to the need to be able to update the list of exceptions thrown. 
  Using a structured syntax allows document_throws to extract the existing
  list and update it should the list of exceptions change.

  Free-form "Throws ..." sentences are not treated as documentation by default.
  Use @Throwing for any exception you want to document. If you want to honor
  free-form doc mentions when running the fix tool, use `dt-fix --honor-doc-mentions`.

#### Basic form
The basic form of the doc comment takes the form:

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

#### reason
For both the doc comments and the annotations you can provide a reason
as to why the exception is thrown.

##### Basic:
```
/// @Throwing(ArgumentError, reason: "You passed an invalid argument")
```

##### Annotation:
```
@Throwing(ArgumentError, reason: "You passed an invalid argument")
```



### Annotations
The annotation form is identical to the dart doc form except that it
is a Dart Annotation.

To use the annotation form you need to add document_throws_annotation to
your dependency list. This is a tiny package with no transient dependencies, it only
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

#### Indexer
All users of the document_throws package need to run the indexer.

The indexer scans all dependency as well as the Dart and Flutter SDK
source code and creates an index detailing every method that throws an
exception and the list of exceptions. 

Both the bulk fix tool and the lints rely on the indexer.

You will need to re-run the indexer each time you update your set of
project  dependencies (inlcuding version changes) or when you update
your Dart or Flutter SDK versions.


The document_throws package includes a lint that will warn if the 
indexer is out of dart `throws_index_up_to_date`.


The indexer places binary indexes into your PUB_CACHE directory.
If you run `dart pub cache reset` or indices will also be reset
and you will need to re-run the index tool.

The indexes are global, so whilst you need to run the indexer
from each Dart applications root directory, it doesn't need
to index 3rd party packages or the SDK if it they have already
been indexed via another Dart application.


#### Bulk Fix tool
The bulk fix tool can add @Throwing documentation to you entire
code base (or a specific library) in a single pass.
Before running the Bulk Fix tool you need to have first run the
indexer in your applications project root.

The build fix tool is able to add new @Throwing documentation as
well as removing @Throwing documentaiton that no longer applies.


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
To enable the plugin,

Add to `analysis_options.yaml`:

```yaml
plugins:
  document_throws:
```


To use the index tool (required) and the bulk fix tool you need to 
globally activate document_throws.

```
dart pub global activate document_throws
```

### Running the indexer.

After globally activating document_throws you need to run the indexer
in each Dart applications root directory.

```
cd <my Dart application root>
dt-index
```

The indexer will take a few minutes the first time you run it.

If your indexes get corrupted for some reason you can force them to be recreated
via `dt-index --recreate`.

## Running the Bulk Fix tool

NOTE: before running the bulk fix tool we recommend that you check in all
current changes so that you can rever the bulk fix if it causes unexpected
problems.

The bulk fix tool can add new exceptions or remove exceptions that no longer
apply.
You can run it for your entire project (recommended) or for an individual library.

To update your exception documentation for the entire project run:

```
cd <my Dart application root>
dt-fix
```

By default dt-fix ignores free-form doc comment mentions and relies on @Throwing.
If you want to honor free-form mentions when running the fix tool, pass:

```
dt-fix --honor-doc-mentions
```

If you want use the annotation form rather than the doc comment form then run:

```
cd <my Dart application root>
dt-fix --annotation
```

The `dart_throws` package includes a more detailed form of the @Throwing annotation
that includes the name of the called method that throw the exception as
well as the exact method that originates the thrown exception.  This 
is mainly used to aid in debugging `document_throws` but it can sometimes
be useful so we have made it availble via the public API.

To update your code base to use the detailed form run:

```
dt-fix --origin
```

To revert back to the shorter form run:

```
dt-fix
```

if you want to use the annotation form of documetation then you must add
the `document_throws_annotation` dependency to your package and run:

```
dart pub global activate document_throws
dt-index
dt-fix --annotation
```

## CI/CD integration for package maintainers

If you are a package developer we strongly recommend that you include the
bulk fixer in your release pipeline to ensure that your exception
documentation is always up to date.

Run the indexer and fix tool in CI to keep `@Throwing` doc comments aligned
with the latest code before cutting a release. Doc comment mode does not
require a package dependency, so the CI job can use the global tool without
changing `pubspec.yaml`.

Example:

```
dart pub global activate document_throws
cd <package root>
dt-index
dt-fix 
```

If you want the pipeline to fail when documentation is out of date, check for
modified files after running the fix tool and exit non-zero when changes are
present.

### Performance
The indexer can take a few minutes to run so if possible store the PUB_CACHE
on a persistent volume.

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
          dt-fix 
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
    - dt-fix 
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
that prefer structured metadata in code and are happy to depending on 
the `document_throws_annotation`  package.

The annotation is named `@Throwing` to avoid clashes with `Throws` in the test
package while still describing its intent.
