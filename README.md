# Not an offical lint package

This linter inclues every non-clashing lints.

## How to enable these lints

To enable these lints for your apps or package:

1.  In a terminal, located at the root of your package, run this command:

    ```terminal
    dart pub add --dev lint_hard
    ```

2.  Create a new `analysis_options.yaml` file, next to the pubspec, that
    includes the lint_hard package:

    ```yaml
    include: package:lint_hard/all.yaml
    ```

## Customizing the predefined lint sets

You can customize the predefined lint sets, both to disable one or more of the
lints included, or to add additional lints. For details see [customizing static
analysis].

