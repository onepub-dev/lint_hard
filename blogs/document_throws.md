# Keeping exception docs in sync with document_throws

The Dart idiomatic way of handling errors is via  unchecked exceptions.

This presents some problems as often when making a call to a method we can't
determine what exceptions need to be handled. 

The Dart style guide tells is to document these execeptions a doc comments
above each method, the problem with this approach is that even the Dart Sdk
doesn't do this consistently, third party packages are a shit show and well
if you are anything like my my own code is worse.

This is even worse when we remember that when trying to determine
the list of exceptoins, that its not just the immediate method
we are calling but any method it calls into third party packages and down
into the bowels of the sdk. 

The result is that exception documenation is either non-existant or can't 
be trusted.

The document_throws package aims to make exception documenation reliable
by automating the documentation of exception to provide an *exhaustive* list
of exceptions.

By *exhasutive* we mean that we document all of the exceptions the method
throws including any originating right down its call stack into third party
packages and the dart sdk.

We also remove documentation of exceptions which are not actually throw
by the method.

So document_throws aims to put the trust back into documented exceptions.

## The tools
document_throws provides three tools to solve this problem.
1. a cli tool (dt-index) to build an index of every method and the exceptions it throws
2. a cli tool (dt-fix) to update the documenation across the entire project.
3. a custom linter

### The indexer
The indexer is run from within your package directory and automatically
indexes ever package dependency (including transitive dependencies) 
and the flutter and sdk versions.

If you update a package dependency or the flutter or dart sdk versions then
you will need to re-run the indexer.
There is a lint that will warn you if you index is out of date.

### The fixer
The fixer works in a similar manner to dart fix.  Run `dt-fix` from the 
root of you dart project and it will update the documenation on every method.

NOTE: ensure that you check all of you source code into git before running
the fixer so that you can revert changes if necessary.

The fixer is able to update existing exception documetation, adding and
removing documentation as necessary.

### The Linter
The linter provides feed back as you code. If you are missing exception 
documentation or have documented an exception that is no longer thrown the
linter will warn you.
The linter also comes with a 'fix' option which allows you to quickly fix your
documatation hands free.
The linter also warns you if you need to update your index.

#### third party and sdk exceptions.
The linter has a secondary purpose. Even though we have indexed your
sdk and third party packages there is no mechanism in your IDE to 
show you what exceptions a called method throws.

The linter helps with this. After you add a call into a method that throws,
the linter will kick in and tell you that you have an exception that is
been throw but hasn't been documented. 

You now know what exceptions to catch (or not).  If you catch an exception
then the linter knows that its nolonger been throw and will tell you to 
remove the documentation for that exception.

## The indexes
The best tool ideas are useless unless the reliable, easy to use, and performant.
document_throws aims to address each of these issues.

In order for document_throws to document your method it needs to know every
method you call, the methods those methods call and so on right down into the
sdk. 

To known this, document_throws builds an index of every package dependency
your project uses as well as an index for the dart and flutter sdk.

The indexes are shared (via PUB_CACHE) so you only need to build an index,
for a given package or sdk version, once and its shared by all packages.

If you run `dart pub cache reset` then you indices will be reset (deleted) as
well and you will need to re-run `dt-index` in each project.

The indices are binary which makes accessing the indexes fast.

## Install and enable

To get started with document_throws lets get it installed.

Add the package as a dev dependency and enable the plugin in `analysis_options.yaml`.

```bash
dart pub add --dev document_throws
```

In your `analysis_options.yaml` add.
```yaml
plugins:
  document_throws:
```

To enable the document_throws cli tooling you must globally activate it

```
dart pub global activate document_throws
```

## Index your project
To get started you must first index your project run:

```
cd <my project>
dt-index
```

This can take a few minutes to run, so go get a coffee.

## The structured doc comment form

The document_throws uses a structured approach to documenting each exception
as this allows us to automate updating the comments.
This does goes against Dart's style guide but experiments showed that 
the more relax form suggested by the Dart style guide just wasn't going
to be practical if we wanted to automate keeping the documents up to date.

The default format is a structured tag inside a doc comment. It reads well in the IDE, and it can be updated by tooling when exceptions change.

```dart
/// @Throwing(ArgumentError)
/// @Throwing(StateError)
void openSession(String token) {
  if (token.isEmpty) {
    throw ArgumentError('token is required');
  }
  if (!_isReady) {
    throw StateError('service not ready');
  }
}
```

You can add a reason when it helps callers understand the condition.

```dart
/// @Throwing(FormatException, reason: 'Invalid header format')
void parseHeader(String header) {
  if (!header.contains(':')) {
    throw FormatException('Missing colon');
  }
}
```

## The annotation form

If you prefer annotations to doc comments, add the annotation package and switch the documentation style.

NOTE: we recommend using the above documentation style as most IDE's
will show the documentation for a method if you hover your mouse over
a call site.  The annotation form will not be shown by your IDE although
the VS-Code 'peak definition' context menu item will show the annotation.


If you still want to use annotations then you will need to add the 
`document_throws_annotation` package to your project. Its a tiny 
package that has a single purpose - to define the annotations. It brings in
zero dependencies. 

```bash
dart pub add document_throws_annotation
```


To enable the linter fixes to use the annotation style you need to enable
it in your `analysis_options.yaml` file. 

`analysis_options.yaml`
```yaml
plugins:
  document_throws:
    documentation_style: annotation
```
The annotation itself is the same structure, just expressed as code.

```dart
import 'package:document_throws_annotation/document_throws_annotation.dart';

@Throwing(ArgumentError, reason: 'token is required')
void openSession(String token) {
  if (token.isEmpty) {
    throw ArgumentError('token is required');
  }
}
```

## The fixer
You now have an index built by way of `dt-index` and you have selected
your choose annotation style.

The next actions is to do a bulk update of your code to apply exception documentation 
across your code base.

Run:
```
cd <my project>
dt-fix
```

or if you are using the annotation style 

Run:
```
cd <my project>
dt-fix --annotations
```

### Free form prose
If you want the fixer to honor free‑form "Throws ..." prose in existing docs, you can opt in.

```bash
dt-fix --honor-doc-mentions
```

This attempts to detect existing throws documentation and suppress the form
notation, but this process isn't always successful given the very large number
of ways the documentation can be express gramatically.

### advanced fixer options

The fixer can provide additional information about each exception that is 
being thrown, including:
* the method call site that that throws the exception
* the originating source of the exception i.e. the package and source file
that actually calls 'throw'.

This additonal information can occasionally come in hand when trying to 
diagnose difficult exception related issues.

You can toggle this additional information on and off.

#### Enable extended exception information:

To enable the extended information for the entire project run:
```bash
cd <my project>
dt-fix --origin
```

To add it for a single Dart library run:

```bash
cd <my project>
dt-fix --origin <path to dart library>
```

To remove the extended information run:

For the entire project.
```bash
cd <my project>
dt-fix 
```

To add it for a single Dart library run:

```bash
cd <my project>
dt-fix  <path to dart library>
```

When you remove the extended information, your 'reasons' clause will
be retained.

## Lints you will see

The plugin includes lints that focus on documentation integrity. The two you will notice first are:

- `document_thrown_exceptions` when something is thrown but not documented
- `unthrown_exceptions_documented` when documentation lists an exception that is not thrown

Those two usually catch drift quickly and are enough to keep docs aligned day‑to‑day.
