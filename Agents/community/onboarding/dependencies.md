# Onboarding Agent Dependencies

The **Onboarding Agent** depends on the following shared components and services:

- Reads shared policies from `policies/`.
- Follows workflows defined under `workflows/`.
- Coordinates with the **Discord Orchestrator**.
- May interact with GameOps and Business agents via orchestrators.

## Notes

- Dependencies SHOULD be invoked via well-defined APIs or orchestration workflows.
- Direct ad-hoc coupling to other agents SHOULD be avoided; instead, use orchestrators where possible.
