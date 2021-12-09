# Not an offical lint package

The objective of lint_hard to improve code quality and consistency and turn runtime errors into compile time errors.

Lint Hard includes every non-clashing dart lint and enables strong mode type checks.

```yaml
strong-mode:
    implicit-casts: false
    implicit-dynamic: false
```

This requires you to do a little more work as your code but will significantly reduce runtime errors saving far more time than you will spend cleaning your lints.


## How to enable Lint Hard

To enable lint_hard for your apps or package:

1. Check in any existing code changes.

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

