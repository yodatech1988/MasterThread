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
- **Shop** — builds this week's grocery list from the pantry/recipes/plan,
  splits it into a Sam's Club bulk cart and a per-retailer comparison set,
  and calls Instacart directly from the page (see §5).
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
- State (`pantry`, `recipes`, `people`, `week`, `shopping` collections)
  lives in the artifact's own shared database capability, not in browser
  storage or any one person's chat history — every viewer with the link
  reads and writes the same live data.
- Falls back to local, unsynced sample data if the db capability is
  unavailable, so the page still renders.
- Declares the `mcp` runtime capability (`Instacart`: `cart`,
  `search_products`) so the Shop tab can call Instacart directly from the
  browser, as whichever signed-in viewer clicks the button — see §5.
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

**2026-09-25: moved from chat-driven to in-app.** Originally this was a
chat-only action (a person asked a Claude session to shop). It now lives in
the **Shop** tab, which calls Instacart directly from the browser via the
artifact runtime's `mcp` capability — no Claude session needs to be in the
loop for a refresh to happen. The chat-driven path (asking a session that
has this artifact's data plus the Instacart connector) still works as a
fallback and is how the two rounds of comparison carts on 2026-09-25 were
actually built and corrected, before this tab existed.

**How the Shop tab works:**

1. Computes this week's grocery list client-side from the live
   `pantry`/`recipes`/`week` collections: every pantry item currently `Out`
   or `Low`, plus any ingredient a recipe assigned in the current Meal Plan
   needs that isn't already in stock. Regenerated fresh on every refresh —
   never assumed from a prior state.
2. Splits that list in two:
   - **Bulk-eligible** — pantry items in the `Pantry`/`Spices` categories,
     excluding anything bread/bun-shaped (a denylist, since those spoil too
     fast to bulk-buy) — go to a **Sam's Club** cart.
   - **Everything else** (including recipe-only ingredients not tracked in
     the pantry, e.g. meat) goes to the per-retailer comparison set.
3. Calls Instacart's `cart` tool once per retailer (`quick_add_search_queries`,
   `clear_cart: true`) using **whoever clicked "Refresh carts"'** own
   Instacart connection and writes the result (items found, a summary
   string, any checkout URL the payload happens to include) to this
   artifact's `shopping` collection, live for every viewer.
4. A person reads the real **cart total** off each retailer in Instacart
   itself (never visible to the page or to Claude — the connector's
   `search_products` tool states this explicitly) and types it into that
   retailer's "Total $" field — one number per retailer, the whole cart,
   not a per-item price. That's shared, durable state like everything else
   here, and a $/item reference value is computed and shown once it's
   entered.
5. Because every regular retailer shops the identical item list, entered
   totals ARE directly comparable — once typed in, the regular retailers
   re-sort cheapest-first and the lowest gets a "Cheapest entered" badge.
   Sam's Club shops a different (bulk-only) list, so it's excluded from
   that ranking and always shown on its own. This is the one place actual
   cost comparison happens: on human-entered numbers, never on anything
   Claude or the page computed itself.

**"As ingredients are added":** true reactivity (firing the instant a
pantry item changes) isn't possible — nothing watches the artifact
continuously. Instead: an in-app **"Refresh carts"** button for on-demand
runs, plus an automatic refresh **once per calendar day**, triggered by
whoever happens to open the app first that day, if the newest retailer
result is more than 20 hours old. This is the practical meaning of "every
morning" here — not a fixed clock time, and not a server-side cron (a cron
would need to run under someone's account to call Instacart, and doing that
outside of an actual person opening the app felt like the wrong owner for
that action).

**Why no automated "best price" pick:** `search_products`'s own tool
description states prices are shown to the person but never visible to the
calling agent — true whether Claude calls it in chat or the page calls it
directly via `mcp`. There is no price field anywhere in the tool's
structured response. The comparison stays "open N carts, read N totals
yourself," with an optional manual price field for whoever wants the
numbers recorded.

**No confirmed checkout link:** every real `cart` tool call observed so far
(both from chat and, so far, only inferred for the in-page path — not yet
exercised by an actual click, see verification note below) returned cart
contents only, no checkout URL field. The Shop tab checks defensively for
one in the response and renders it as a link only if present; otherwise it
shows "Open Instacart to checkout" as plain text rather than fabricating a
link.

**Comparison retailers (delivery to the household's Mansfield, OH
address):** Kroger, Meijer, ALDI, Giant Eagle, Gordon Food Service Store,
Target, Marc's, Fresh Thyme Market, Village Market, Save A Lot, Buehler's
Fresh Foods, Apples Market, Carfagna's Market, Discount Drug Mart — every
grocery-relevant retailer Instacart offers for this address, plus Sam's
Club for the bulk split. **Not available:** Walmart is not offered as an
Instacart retailer for this address. Item availability varies by store — a
store that doesn't carry an exact item is reported back (found count below
requested count, plus the tool's own summary text) rather than silently
substituted into a materially different product. In practice the
search-match step has occasionally returned a wrong product for a specific
query (e.g. a snack item, or a cucumber, for "gluten-free hamburger buns")
rather than reporting no match when the two rounds of comparison carts were
built by hand on 2026-09-25 — worth a quick eyeball against the intended
list, not just the found/requested count.

**Hard rule: nothing here ever completes checkout, at any retailer, for
anyone.** A person always reviews each cart and finishes the purchase
themselves — this mirrors the existing "confirm before writing on
someone's behalf" rule for pantry/preference data, applied to something
with a real cost. Neither the Shop tab's code nor a Claude session calls
any checkout-completing tool.

**Depends on a personal Instacart connection.** The Shop tab calls
Instacart using whichever signed-in viewer clicks the button — it only
works for someone who has Instacart connected in their own claude.ai
account. It's connected in Jeremy's; it may not be in Natalie's or
Marshall's (n/a at 4). Whoever refreshes builds the carts under their own
Instacart account.

**Verification note:** this session published the `mcp`-capability code and
confirmed the `shopping` collection reads back empty (as expected pre-use),
but could not click the actual "Refresh carts" button as a browser viewer
— that requires a real signed-in session in the app, which this session
doesn't have. The client-side `mcp.callTool` path is built to the
documented contract but unexercised end-to-end; the first real click is
the actual test.

## 6. Non-goals

- Not a general recipe database or meal-planning SaaS product.
- Not a substitute for actual medical/dietary guidance — restriction notes
  describe what to avoid, they don't diagnose or prescribe.
- No standalone deployment/hosting is planned; it stays a Claude Artifact
  unless a real need for one emerges.
- Nothing — page code or Claude session — ever completes an Instacart
  checkout on a person's behalf (see §5).
