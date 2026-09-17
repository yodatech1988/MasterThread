# Test Plan Executor Agent Dependencies

The **Test Plan Executor Agent** depends on the following shared components and services:

- Reads shared policies from `policies/`.
- Follows workflows defined under `workflows/`.
- Coordinates with the **Architect** orchestrator.
- May call GitHub Integration Agent for repo interactions.

## Notes

- Dependencies SHOULD be invoked via well-defined APIs or orchestration workflows.
- Direct ad-hoc coupling to other agents SHOULD be avoided; instead, use orchestrators where possible.
