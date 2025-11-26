    # Incident Agent Dependencies

    The **Incident Agent** depends on the following shared components and services:

    - Reads shared policies from `policies/`.
- Follows workflows defined under `workflows/`.
- Coordinates with the **Game Operations Orchestrator**.
- May consume telemetry and analytics services.

    ## Notes

    - Dependencies SHOULD be invoked via well-defined APIs or orchestration workflows.
    - Direct ad-hoc coupling to other agents SHOULD be avoided; instead, use orchestrators where possible.
