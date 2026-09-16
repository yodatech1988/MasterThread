# Acceptance Criteria Standard

## Purpose
Define clear, testable conditions to determine when a feature or change is "done".

## Rules

- Each feature MUST have acceptance criteria.
- Each criterion MUST be:
  - Binary (pass/fail).
  - Linked to one or more functional requirements.
  - Verifiable via automated or manual tests.

## Format

- Use IDs: `AC-001`, `AC-002`, ...
- Describe:
  - **Preconditions**
  - **Action**
  - **Expected Result**

Agents creating or updating acceptance criteria MUST use this structure and keep IDs stable once referenced in tests.
