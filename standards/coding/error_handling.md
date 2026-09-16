# Error Handling Standard

## Principles

- Fail loudly in logs, fail gracefully in user-facing contexts.
- Prefer explicit error types over generic messages.
- Always include a correlation or request ID.

## Agent Rules

- Surface actionable error messages.
- Never expose secrets in errors.
- When in doubt, escalate instead of guessing.
