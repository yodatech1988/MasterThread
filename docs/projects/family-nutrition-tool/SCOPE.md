# Family Kitchen (family nutrition tool) — Project Scope

**Status:** Built and live as a Claude Artifact. Not a repo/app-code project — this
directory exists to give the tool a durable, version-controlled record outside
any one chat session.
**Owner:** Jeremy Berger
**Live artifact:** https://claude.ai/artifact/PWhXCN6PTy4yLrWoih1Y12

## 1. What it is

"Family Kitchen" is the Berger family's shared kitchen tool, built as a
single-page Claude Artifact (not a standalone repo/deployment). It covers:

- **Pantry** — tracked items with category, quantity, unit, and an
  in-stock/low/out status derived from quantity.
- **Recipes** — title, tags, ingredients, and steps, with an on-the-fly
  "have N/M ingredients" check against the live pantry.
- **Meal Plan** — a rolling week grid (breakfast/lunch/dinner per day) that
  references recipes by id.
- **Preferences** — one card per family member (restrictions, likes,
  dislikes), free text.
- **About & Access** — in-app documentation of scope and the access model
  (see below), including guidance for a Claude session reading the page on
  a family member's behalf.

## 2. Who it's for

Three household members, each with distinct dietary needs the tool exists to
track accurately:

- **Jeremy** — low-FODMAP elimination diet (avoiding garlic/onion, wheat,
  certain fruits/dairy in quantity), plus low-sodium/low-cholesterol for
  blood pressure and cholesterol management.
- **Natalie** — ovo-dairy pescatarian (eggs, dairy, fish/seafood; no meat or
  poultry).
- **Marshall (4)** — generally easy to feed; specific preferences still being
  filled in over time.

The **Preferences** tab in the live artifact is the source of truth for this
— it's expected to change as health needs change, so it should always be
read fresh rather than assumed from an earlier conversation.

## 3. Architecture

- Single HTML/CSS/JS page, no build step, no separate backend.
- State (`pantry`, `recipes`, `people`, `week` collections) lives in the
  artifact's own shared database capability, not in browser storage or any
  one person's chat history — every viewer with the link reads and writes
  the same live data.
- Falls back to local, unsynced sample data if the db capability is
  unavailable, so the page still renders.
- A copy of the page source as of this write-up is kept at
  [`artifact-source.html`](./artifact-source.html) in this directory, purely
  as a version-controlled backup — the live artifact is the actual running
  system; this repo does not deploy or serve it.

## 4. Access model

Anyone who can open the artifact link can both read and write its data —
there is no separate read-only role enforced today. Practical consequence:
**the link itself is the access control.** Share it only with people in the
household. Nothing sensitive (passwords, financial info, full medical
records) belongs in it — dietary notes only.

## 5. Non-goals

- Not a general recipe database or meal-planning SaaS product.
- Not a substitute for actual medical/dietary guidance — restriction notes
  describe what to avoid, they don't diagnose or prescribe.
- No standalone deployment/hosting is planned; it stays a Claude Artifact
  unless a real need for one emerges.
