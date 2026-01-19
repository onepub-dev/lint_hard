# Lambda Throws (Design)

## Summary
The lint currently reports thrown exceptions for executable declarations
(methods, functions, constructors). It does not report throws for closures
or anonymous functions.

## Rationale
Closures are often used as arguments or local values, and annotating them
with `@Throwing` does not map cleanly to a declaration that tools can surface.
Adding annotations to local variables would be noisy and requires additional
syntax conventions.

## Decision
Do not document lambda throws for now. Exceptions thrown inside closures are
reported at the enclosing executable declaration when they escape the closure
and are not handled.

## Possible future extension
- Allow `@Throwing` on top-level or class fields that hold function values.
- Provide a lint to warn when closures throw unhandled exceptions.
