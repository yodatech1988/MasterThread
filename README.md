# MasterThread

Central trunk for all AI + DayZ automation projects.

MasterThread is **not a code repo** – it is the **source of truth for
direction, architecture, and coordination** across all related services:

- 🧠 AutoGPT Workflows Repository
- 🤖 Discord Automation Agent
- ⚙️ DayZ Server Automations
- 💰 Patreon / Subscription Automation System
- 📦 DayZ Server Configuration & State Repository
- 🛠️ Software Development Automation
- 💬 Multi-Use Chat Interface (and any future services)

---

## Goals

- Provide a single place to understand **what exists**, **why it exists**, and
  **how it fits together**.
- Capture **architecture diagrams, roadmaps, and decisions** that span multiple repos.
- Track **cross-cutting issues** and **epics** that affect more than one service.
- Serve as a high-level onboarding guide for future collaborators (or future you).

---

## Key Documents

- [`docs/OVERVIEW.md`](docs/OVERVIEW.md) – High-level description of the entire platform.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) – System diagrams and dataflows.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) – Global roadmap with milestones by quarter.
- [`docs/REPOS.md`](docs/REPOS.md) – Inventory of all related repositories.
- [`docs/WORKSTREAMS.md`](docs/WORKSTREAMS.md) – Breakdown by domain (Discord, DayZ, Patreon, Infra).
- [`decisions/`](decisions/) – Architecture Decision Records (ADRs) documenting major choices.

---

## How to Use This Repo

1. **Start here** when planning a new feature that touches multiple repos.
2. Create or update a **project page** under `projects/` that:
   - Links to the involved repos and issues.
   - Defines scope, risks, and done-criteria.
3. If the work represents a big architectural choice, add an ADR under `decisions/`.
4. Use MasterThread issues for:
   - Cross-repo epics
   - High-level planning
   - “Boss fight” tasks that require several services to move in sync.

---

## Related Repositories

See [`docs/REPOS.md`](docs/REPOS.md) for the most up-to-date list and links.

---

## Contributing

This repo is mostly **markdown + diagrams**. No code changes required:

- Update docs in `docs/` when the architecture or roadmap changes.
- Add ADRs in `decisions/` when making big, irreversible decisions.
- Keep project pages in `projects/` updated as work progresses.
