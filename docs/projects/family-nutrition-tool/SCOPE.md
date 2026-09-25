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

**2026-09-25 correction:** "Jeremy's Lightened-Up Cheeseburger" (recipe
`r3`) already dropped garlic/onion for low-FODMAP, but still called for
whole wheat hamburger buns — wheat bread is high-FODMAP (fructans) well
above the low-FODMAP serving threshold, despite the recipe being
explicitly labeled for Jeremy. Fixed live in the artifact db: the
ingredient and matching pantry item (`p12`) now read "gluten-free
hamburger buns," and the recipe is tagged `low-FODMAP`. Grocery carts
already built for the week were updated to match. Not every store in the
comparison set carries a gluten-free bun (ALDI and Gordon Food Service
Store didn't have a match) — worth a manual check or a swap to a
different retailer for that one item.
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

## 5. Instacart integration

Shopping is chat-driven, not an in-app button — there is no "Shop" tab on
the artifact itself. A person asks a Claude session (one with both this
artifact's data and the Instacart connector available) to shop, and that
session:

1. Reads current state from the artifact's live `pantry`/`recipes`/`week`
   collections (never assumes it from an earlier conversation, per the
   access-model note above).
2. Builds the item list for one of two distinct actions:
   - **Restock** — every pantry item currently `Out` or `Low`.
   - **Shop the plan** — ingredients required by the recipes assigned in
     the current week's Meal Plan that aren't already in stock.
   These are separate asks (e.g. "order what's low" vs. "shop for this
   week's plan") and are never combined silently.
3. Splits that item list in two:
   - **Bulk-eligible items** — shelf-stable staples only (oils, spices,
     rice, canned/frozen goods, paper goods — nothing that spoils before a
     family of 3 uses it up) go to a **Sam's Club** cart.
   - **Everything else** goes to a price-comparison pass across the
     household's regular retailers (see below).
4. For the non-bulk items, builds one Instacart cart per retailer with the
   same item list, then hands back all the cart links together — it does
   **not** pick a "best price" retailer itself.

**Why comparison carts instead of a single pick: the Instacart tools never
expose prices to the agent** — `search_products`'s own description states
prices are shown to the person but not visible to the AI. A person opens
each cart in Instacart and compares totals themselves; Claude cannot do
this arithmetic for them.

**Comparison retailers (delivery to the household's Mansfield, OH
address):** Kroger, Meijer, ALDI, Giant Eagle, Gordon Food Service Store.
Also available at this address if ever swapped in: Target, Marc's, Fresh
Thyme Market. **Not available:** Walmart is not offered as an Instacart
retailer for this address. Item availability varies by store — a store
that doesn't carry an exact item (e.g. a specific pack size) is reported
back rather than silently substituted into a materially different product.

**Hard rule: Claude adds to carts but never completes checkout, at any
retailer.** A person always reviews each cart and finishes the purchase
themselves — this mirrors the existing "confirm before writing on
someone's behalf" rule for pantry/preference data, applied to something
with a real cost.

This is a chat-time behavior, not code shipped anywhere — there's nothing
to build or deploy for it, so it isn't reflected in `artifact-source.html`.
This section is the durable record of how it's expected to work.

## 6. Non-goals

- Not a general recipe database or meal-planning SaaS product.
- Not a substitute for actual medical/dietary guidance — restriction notes
  describe what to avoid, they don't diagnose or prescribe.
- No standalone deployment/hosting is planned; it stays a Claude Artifact
  unless a real need for one emerges.
- No in-app Instacart button/UI — shopping stays a chat-driven action (see
  §5), and no session completes a checkout on a person's behalf.
