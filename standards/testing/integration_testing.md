# Integration Testing Standard

## Purpose
Verify that services and agents interact correctly across boundaries.

## Scope

- API compatibility.
- Data contract adherence.
- Telemetry and logging.
- Cross-service workflows (e.g., Patreon -> DayZ -> Discord).

## Guidelines

- Focus on realistic flows, not just individual functions.
- Use representative test data.
- Log all external calls and responses.

Integration tests MUST run before any release affecting multiple systems.
