# Functional Requirements Standard

## Purpose
Define a consistent structure for functional requirements so that all agents and humans can read, interpret, and automate them reliably.

## Sections

Each functional requirements document MUST include:

1. **Overview**
   - Short description of the feature or change.
   - Business / gameplay context.

2. **Actors**
   - Human roles (e.g., Player, Admin, Moderator).
   - System roles (e.g., DayZ Server, Discord Bot, Patreon Engine).

3. **User-Facing Requirements**
   - Numbered list: `FR-001`, `FR-002`, ...
   - Each requirement MUST:
     - Describe *what* the system should do, not *how*.
     - Be testable.
     - Be written in plain language.

4. **Non-Functional Notes (Optional)**
   - Performance expectations.
   - UX constraints.
   - Compatibility notes.

5. **Traceability**
   - Link to original issue, ticket, or request.
   - Link to related design documents and tests.

Agents that generate functional requirements MUST follow this structure and ID convention.
