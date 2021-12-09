# Not an offical lint package

This linter inclues every non-clashing lints.

## How to enable these lints

To enable these lints for your apps or package:

1. Checking any existing code changes.

2.  In a terminal, located at the root of your package, run this command:

    ```terminal
    dart pub add --dev lint_hard
    ```

3.  Create or modify your `analysis_options.yaml` file in the root of your project, that
    includes the lint_hard package:

    ```yaml
    include: package:lint_hard/all.yaml
    ```

4. run dart fix

The dart fix command will apply a number of automated fixes based on the lint_hard settings.

Run:
```bash
dart fix --apply
```
Re-run dart fix until it reports 'Nothing to fix!'

## Customizing the predefined lint sets

You can customize the predefined lint sets, both to disable one or more of the
lints included, or to add additional lints. For details see [customizing static
analysis].

