# Naming Conventions Standard

## General

- Use `snake_case` for JSON keys and database columns.
- Use `camelCase` or `PascalCase` depending on language norms for code identifiers.
- Agent names SHOULD be descriptive of their function.

## IDs

- Use UUIDs for globally unique IDs when not tied to external systems.
- Use stable slugs or short codes where human readability matters.

Code Generator and Code Reviewer Agents MUST enforce these conventions.
