    # Entitlement Policy Agent Dependencies

    The **Entitlement Policy Agent** depends on the following shared components and services:

    - Reads shared policies from `policies/`.
- Follows workflows defined under `workflows/`.
- Coordinates with the **Patreon Orchestrator** or business workflows.
- May call finance-related services or analytics pipelines.

    ## Notes

    - Dependencies SHOULD be invoked via well-defined APIs or orchestration workflows.
    - Direct ad-hoc coupling to other agents SHOULD be avoided; instead, use orchestrators where possible.
