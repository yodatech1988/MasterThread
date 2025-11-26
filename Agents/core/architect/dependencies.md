    # Architect Agent Dependencies

    The **Architect Agent** depends on the following shared components and services:

    - Reads shared policies from `policies/`.
- Follows workflows defined under `workflows/`.
- Serves as a dependency for multiple domains as a core utility/orchestrator.

    ## Notes

    - Dependencies SHOULD be invoked via well-defined APIs or orchestration workflows.
    - Direct ad-hoc coupling to other agents SHOULD be avoided; instead, use orchestrators where possible.
