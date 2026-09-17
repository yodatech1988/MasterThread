# Monitoring Gameops Agent Escalation Rules

The **Monitoring Gameops Agent** MUST escalate in the following situations:

## 1. Policy Conflicts
- When requested behavior appears to conflict with policies in `policies/`.
- Action: halt execution, emit a warning output, and notify the relevant orchestrator.

## 2. Ambiguous or Unsafe Instructions
- When the inputs are unclear, contradictory, or could cause irreversible harm (data loss, permanent bans, financial loss).
- Action: request clarification via the orchestrator or mark the task as requiring human review.

## 3. External System Failures
- When dependent services (e.g., DayZ server, Discord API, Patreon API, GitHub) are unavailable or returning errors.
- Action: stop, log the failure, and return a retry-friendly error description.

## 4. Human-Only Decisions
- Legal, financial, or security-sensitive decisions that have not been explicitly delegated.
- Action: summarize the situation and escalate to a human operator or governance orchestrator.

## Escalation Targets

- Primary: the relevant **orchestrator** for this domain.
- Secondary: the **Governance Orchestrator** for cross-domain or policy-level issues.
