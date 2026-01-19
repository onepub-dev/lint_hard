# Objective (Design)

## Objective
Document exceptions thrown by user code and external dependencies, including
SDK libraries, while keeping the annotations accurate and actionable.

## Constraints
- IDEs do not surface custom annotations in hover text for external packages.
- The index provides external provenance but is not visible in IDE tooling.

## Direction
- Keep `@Throwing` as the source of truth for user code.
- Use the index to warn about undocumented exceptions and to power fixes.
- Consider a lightweight editor extension to surface indexed throws for SDK
  and dependency symbols.

## Open work
- Evaluate editor support requirements for VS Code and Android Studio.
- Prototype a VS Code extension using the language server or custom hover
  provider to expose indexed throws.
