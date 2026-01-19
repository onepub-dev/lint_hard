# Lint Hard

The objective of lint_hard is to reduce the accumulation of technical debt by
improving code quality and consistency while turning runtime errors into
compile time errors.

Lint Hard uses strict type checks to improve code clarity and remove ambiguity
in loosely typed code. It turns many common runtime errors into compile time
errors, and that usually saves more time than it costs to address lints.

Lint Hard forces consistent standards across your code base, which makes it
easier to read and maintain.

## Drop-in replacement
You can use Lint Hard as a drop-in replacement for existing lint packages
(pedantic, lints, flutter_lints).


## What lints are included
Lint Hard includes every non-clashing Dart lint and enables strict language
checks. A few lints that conflict with these goals are disabled.

```yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

You can see the full set of lints in `package:lint_hard/all.yaml`.

## Installing Lint Hard

1. Check in any existing code changes.
2. Run `dart format` and check in the formatting changes.
3. Add the package:

    ```terminal
    dart pub add --dev lint_hard
    ```

4. Create or modify `analysis_options.yaml`:

    ```yaml
    include: package:lint_hard/all.yaml

    plugins:
      lint_hard:
        diagnostics:
          document_thrown_exceptions: true
          throws_index_up_to_date: true
          fields_first_constructors_next: true
          documented_unthrown_exception: true
    ```

   To disable custom lint_hard plugin lints while keeping the lint set,
   remove the `plugins` block or set the diagnostics to `false`.

5. Remove any existing lint packages (lints, pedantic, flutter_lints) from
your `pubspec.yaml` and `analysis_options.yaml`.
6. Run `dart pub get`
7. Run `dart fix --apply` until it reports "Nothing to fix!".
8. Run `dart format` again if needed.
9. Restart the Dart analysis server in your IDE.

## Manually fixing lints
The `dart fix` command will not fix all lints, so you will need to work through
the remaining lints by hand.

This can be overwhelming at first. Filtering warnings and tackling one rule at
a time usually helps. If you cannot fix everything immediately, temporarily
disable specific rules and re-enable them as you make progress.

After you fix the initial batch, new warnings tend to be fewer and easier to
handle.

e.g.
```yaml
linter:
  rules:
    avoid_print: false
```

## Console app development
For console apps that use `print`, add this to `analysis_options.yaml`:

```yaml
linter:
  rules:
    avoid_print: false
```

## documenting thrown exceptions

The `document_thrown_exceptions` lint uses `@Throwing` tags in doc comments by
default. You can also use `@Throwing` annotations with the annotation package.

Doc comment example:

```dart
/// @Throwing(FormatException)
void parseInput(String value) {
  throw FormatException('Invalid input');
}
```

Annotation example:

```dart
import 'package:document_throws_annotation/document_throws_annotation.dart';

@Throwing(FormatException, reason: 'Bad format')
void parseWithReason(String value) {
  throw FormatException('Invalid input');
}
```

Build the external throws cache once per SDK or package update:

```terminal
document_throws_index
```

Use `--no-sdk`, `--no-packages`, or `--no-flutter` to limit indexing.

In VS Code you can view `@Throwing` annotations using Peek Definition:
right-click the function name and select "Peek Definition", or press
`Alt+F12` with the caret on the symbol.

## other improvements

The Lint Hard project also offers the following advice to help you improve the overall quality of your project.

Or you can just jump to the bottom of this page to [install](#installing-lint-hard) Lint Hard.

## Dart format
We strongly recommend that you use `dart format` to format your code.  Whilst personally I don't like some of the formatting decisions imposed by dart format, consistency is more important.  Don't fight this one. Just run `dart format` with no options. You will get used to the format and it makes sharing code with other developers easier. 
Using `dart format` will also make it easier for you to read other developer's code as `dart format` is almost universally used in the Dart community.

dart format will improve your commit history as it won't be fouled with format differences. This is particularly important  in a team project but will render dividends even if you work alone. 

Use an IDE like vs-code that automatically formats your code each time you save it.

**_Only commit code that has been formatted._**


## A word to JavaScript developers
If you are coming from the JavaScript world, enforcing type declarations may initially feel burdensome but you will quickly see that it allows you to develop faster and release quality code sooner.   

## Avoid dynamic and Object types

For the most part you should never use the dynamic type and rarely use the Object type.

There are exceptions to these rules such as when parsing json dart. But you should always try to use an actual type. dynamic and Object should be last resorts.

## Adjustments for package developers

If you are building a dart package then you should be adding documentation to all of your public methods as well as ensuring that all public apis have type information.

To ensure you do this consistently add the following to you analysis_options.yaml:

```yaml
linter:
  rules:
    public_member_api_docs : true 
    type_annotate_public_apis: true
```

Adding the annotation type_annotate_public_apis will cause a warning

## Use nnbd

This one probably doesn't need to be said, but just in case...

If you haven't already moved your project to Not Null by Default (nnbd) now is the time to do it.
We do recommend applying Lint Hard to your project first and then doing the nnbd conversion. A cleaner code base will help the nnbd migration tool.

Now you have nnbd enabled, try to minimize the use of '?' operator. Use non-nullable types as your default. Only use a nullable type if the variable really needs to be nullable.

Use techniques such as default values and (carefully) the `late` keyword.




## Customizing the predefined lint sets

You can customize the predefined lint set, both to disable a
lint or to add additional lints. For details see
[customizing static analysis](https://dart.dev/tools/analysis#configuring-the-analyzer).


# Updating lint_hard
We need to keep lint_hard up to date with the latest list of lints.

We can find a complete set of lints at:
[All Lint Rules](https://dart.dev/tools/linter-rules/all)
