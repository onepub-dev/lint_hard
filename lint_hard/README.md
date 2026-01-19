# Lint Hard 

The objective of lint_hard is to reduced the accumulation of technical debt by improving code quality and consistency whilst turning runtime errors into compile time errors.


Lint Hard employs strong mode type saftey to improve code clarity and remove 'ambiguity of intent' found in typeless or softly typed code.

Lint Hard turns many of the common runtime errors into compile time errors. The rule of thumb is that it is 10 times harder to fix a runtime error than a compiler error. Lint Hard will save you time and frustration.  

Using Lint Hard will require you to do a little more work as you code but will significantly reduce runtime errors, saving far more time than you will spend cleaning your lints. The `dart fix` command also automates fixing many of the most common lints reducing the workload.

Lint Hard forces you to use consistent standards across your code base which makes it easier for other developers to read your code. It will also help when you come back to your code in 12 months time.

## drop in replacement
You can use Lint Hard as a drop in replacement for your existing lint package (pedantic, lints, flutter_lints ...).


## what lints are included
Lint Hard includes every non-clashing dart lint and enables strong mode type checks. We do remove a few lints that make little sense given our objectives.

```yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  strong-mode:
    implicit-casts: false
    implicit-dynamic: false
```

You can see the full set of lints in the analysis_options.yaml file.

## installing Lint Hard

1. Check in any existing code changes.
2. Run `dart format` and check in the formatting changes.
3. Add the package:

    ```terminal
    dart pub add --dev lint_hard
    ```

4. Create or modify `analysis_options.yaml`:

    ```yaml
    include: package:lint_hard/all.yaml
    # enable lint_hard custom lints - these add a performance overhead of 
    # about 20 seconds to the first run of dart analyze
    plugins:
      lint_hard:
    ```

   To disable custom lint_hard plugin lints while keeping the lint set,
   override the plugin list:

   ```yaml
   analyzer:
     plugins: []
   ```

5. Remove any existing lint packages (lints, pedantic, flutter_lints) from
your `pubspec.yaml` and `analysis_options.yaml`.
6. Run `dart pub get`
7. Run `dart fix --apply` until it reports "Nothing to fix!".
8. Run `dart format` again if needed.
9. Restart the Dart analysis server in your IDE.

## Manually fixing lints
The `dart fix` command will not fix all of your lints, so you now need to 
work through the remaing lints by hand.

This can be a bit overwhelming to begin with, so I recommend a couple of 
approaches.
Filter the list of warnings (most IDEs allow this) and focus on fixing
one type of lint at a time.
If you can't fix all of the lints immediately you can temporarily disable
some lints via adding a rule to your `analysis_options.yaml`.
Remember to go back and re-enable them as you slow work through the full
set of lints.

Don't get discourage once you have fixed all of your lints, new warnings
will be fewer and easier to fix.

e.g.
```yaml
linter:
  rules:
    avoid_print: false
```

## Consle app development
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

## dart format
We strongly recommend that you use `dart format` to format your code.  Whilst personally I don't like some of the formatting decisions imposed by dart format, consistency is more important.  Don't fight this one. Just run `dart format` with no options. You will get used to the format and it makes sharing code with other developers easier. 
Using `dart format` will also make it easier for you to read other developer's code as `dart format` is almost universally used in the Dart community.

dart format will improve your commit history as it won't be fouled with format differences. This is particularly important  in a team project but will render dividends even if you work alone. 

Use an IDE like vs-code that automatically formats your code each time you save it.

**_Only commit code that has been formatted._**


## a word to JavaScript developers
If you are coming from the JavaScript world, enforcing type declarations may initially feel burdensome but you will quickly see that it allows you to develop faster and release quality code sooner.   

## avoid dynamic and Object types

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




## customizing the predefined lint sets

You can customize the predefined lint set, both to disable a
lint or to add additional lints. For details see
[customizing static analysis](https://dart.dev/tools/analysis#configuring-the-analyzer).


# Updating lint_hard
We need to keep lint_hard up to date with the latest list of lints.

We can find a complete set of lints at:
[All Lint Rules](https://dart.dev/tools/linter-rules/all)
