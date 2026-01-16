# Lint Hard 

The objective of lint_hard is to reduced the accumulation of technical debt by improving code quality and consistency whilst turning runtime errors into compile time errors.


Lint Hard employs strong mode type saftey to improve code clarity and remove 'ambiguity of intent' found in typeless or softly typed code.

Lint Hard turns many of the common runtime errors into compile time errors. The rule of thumb is that it is 10 times harder to fix a runtime error than a compiler error. Lint Hard will save you time and frustration.  

Using Lint Hard will require you to do a little more work as you code but will significantly reduce runtime errors saving far more time than you will spend cleaning your lints. The `dart fix` command also automates fixing many of the most common lints reducing the workload.

Lint Hard forces you to use consistent standards across your code base which makes it easier for other developers to read your code. It will also help when you come back to your code in 12 months time.

## drop in replacement
You can use Lint Hard as a drop in replacement for your existing lint package (pedantic, lints, flutter_lints ...).


## what lints are included
Lint Hard includes every non-clashing dart lint and enables strong mode type checks.

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

To install lint_hard into your app or package:

1. Check in any existing code changes.

2. run dart format

    ```terminal
    dart format
    ```
3. Check in the formatted code

    If you already use dart format you can skip this step.
    If you don't currently use dart format this step will make it easier to diff your lint changes as they won't be mingled with format changes.
    
4.  In a terminal, located at the root of your package, run this command:

    ```terminal
    dart pub add --dev lint_hard
    ```

5.  Create or modify the `analysis_options.yaml` file in the root of your project:

    ```yaml
    include: package:lint_hard/all.yaml
    # enable lint hards custom lints - these do add a performance overhead.
    plugins:
      lint_hard:
        path: ..
        diagnostics:
          document_thrown_exceptions: true
          fields_first_constructors_next: true
    ```

5. Remove your existing linter

    If you are using another linter such as lints, pedantic, flutter_lints etc. now is the time to remove it.
    Your existing lint package should be listed in the dev_dependencies section of your projects pubspec.yaml.
    
    If you have been using the pedantic package it may be in the dependencies section. Remove it also.
    
5. run dart fix

    The dart fix command will apply a number of automated fixes based on the lint_hard settings.

    Run:
    ```bash
    dart fix --apply
    ```
    Re-run dart fix until it reports 'Nothing to fix!'

6. run dart format

    Finally run `dart format` over your code. Ideally you should be using an IDE that automatically formats your code whenever you save.
    
7. avoid_print for console users

    Console apps developers should add the following to your project's analysis_options.yaml
    ```
    linter:
      rules:
        avoid_print: false  
    ```

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
lint or to add additional lints. For details see [customizing static
analysis].


# Updating lint_hard
We need to keep lint_hard up to date with the latest list of lints.

We can find a complete set of lints at:
[All Lint Rules](https://dart.dev/tools/linter-rules/all)
