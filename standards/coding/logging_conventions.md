# Logging Conventions Standard

## Goals
Provide machine-readable, human-understandable logs across all services and agents.

## Structure

- Timestamp.
- Level: DEBUG, INFO, WARN, ERROR.
- Component/agent name.
- Correlation/request ID.
- Message.
- Optional: structured fields (JSON).

Agents MUST log key decisions and unusual conditions according to this structure.
