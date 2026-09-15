# AEGIS Directive — Server Operating Donations Plan

**Status:** draft for Jeremy's approval · updated 2026-09-15 · every real value is now known and
wired in — PayPal link, monthly costs, and the funded-through date (website PR
[#27](https://github.com/yodatech1988/website/pull/27), blocked on a pre-existing CI bug, not the
content — see below; services branch `agent/services/fund-embed-donate-link` queued behind
services #93) — still needs the `#fund-the-server` channel/webhook (§3 item 5) and the PR #27 CI
fix below before anything actually goes live.
**PR #27 merge blocker (not content-related):** the required `secret-scan` check crashes because
`gitleaks` can't install — a leftover `/tmp/gitleaks.tmp` stuck in the self-hosted runner's private
`/tmp` (`aegis-gha-runner@website.service` has `PrivateTmp=yes`, so it persists across job runs
until the service restarts). Confirmed via two separate run logs, not a real secret finding.
Branch protection has `enforce_admins: true`, so this needs Jeremy to run
`sudo systemctl restart aegis-gha-runner@website.service` before the PR can merge.
**Scope:** one-time donations of **$5 / $10 / $20 / Other**, shown on aegisdirective.net and the AEGIS Discord.
**What the money is for:** (1) the game-server hosting contract, (2) the OVH VPS that runs the
network's bots/APIs ($10/mo, confirmed 2026-09-15), and (3) Claude API tokens that run the
network's agents. **Changed 2026-09-15** (Jeremy's call) — the VPS wasn't a cost bucket when this
plan was first written; it now runs real infrastructure (`aegis-services` `docs/ops/VPS.md`) and
belongs in the same "what this page is honest about" list as the other two.
**What a donation gets you:** nothing. No in-game item, no perk, no priority queue, no Discord role, no badge.

This is **not** a restart of the paused tiered plan (`site-chernarus/docs/nasdara-monetization-plan.md`).
Paid perks, Ko-fi tiers, priority queue and skin tokens all stay paused. This plan covers donations only.

---

## 1. Why donations can go ahead while the tiered plan is paused

| Check | Result | Source |
|---|---|---|
| Bohemia server-monetization rules | **Allowed without registration.** "Accepting donations" is on the permitted list, as long as not donating never blocks content. Registration is only required for monetization "beyond no-counter-value donations." | monetization plan §Compliance, researched 2026-09-11 |
| Counter-value creep | **Main risk.** A Discord "Supporter" role, a name on an in-game board, or a "thank-you" item counts as counter-value, and then registration is required. That's why this plan has no role and no public donor list by default. | same |
| Trademark | The donation page must carry the existing footer disclaimer ("not affiliated or authorized by Bohemia Interactive a.s."). It must not say "DayZ" in a way that looks official. | §Compliance — trademark |
| Mod licences | **Needs checking (Session 1).** Some mod authors forbid "monetization." Those mods are already blocked in `core/docs/mods/README.md` §4. Still, check the licence wording of every *installed* mod for "donation" before launch. | §Compliance — mod licences |
| Taxes | Donations to Jeremy personally are **not tax-deductible** for donors, and they are taxable income for Jeremy. The page must say so. Keep them in a separate ledger, apart from HandyMansfield's books. | not legal/tax advice — confirm with a tax preparer |

---

## 2. Decisions (defaulted; change any before Session 1)

| # | Decision | Default | Why |
|---|---|---|---|
| D1 | Platform | **PayPal** (business account), via a single embedded PayPal `Donation.Button` widget (`hosted_button_id=XRUFPV3ECAETC`) with $5/$10/$20/Other configured on PayPal's side, plus a plain `paypal.com/donate/?hosted_button_id=...` fallback link for blocked JS | **Changed 2026-09-12, Jeremy's call, superseding the pre-pause Ko-fi decision.** Reason: the same account can also pay mod-pack purchases and paid services for the server, instead of collecting on Ko-fi and moving funds elsewhere before spending. **Refined 2026-09-15:** the originally-planned four separate `paypal.me/<handle>/<amount>` links were replaced by Jeremy's actual PayPal hosted donate button — same zero-backend property, one embed instead of four links, and it's what PayPal's own SDK expects (`developer.paypal.com/sdk/donate/`). Explicitly scoped to **link/embed only, no order-create/capture API or webhooks** ("link now, add tracking later" — Jeremy's call 2026-09-15); webhook-driven tracking stays a Session 4 later-not-now item. **Trade-off:** standard PayPal commercial transaction fees apply to every donation (no 0%-fee donation path — PayPal's fee-free donate button requires 501(c)(3) nonprofit status, which doesn't apply here). **Fallback:** Stripe Payment Links, if this ever needs to change per-currency or per-region. |
| D2 | Recurring monthly option | **Off at launch** | A monthly option reads like a subscription, and subscribers expect something back. It can be added later as "monthly, still no benefit." |
| D3 | "Other" minimum | **$3** | PayPal's fee has a fixed-cents component on top of the percentage; below about $3 it eats too much of the gift. |
| D4 | Discord role / donor wall | **None** | This keeps the "no counter-value" position clean. A private thank-you DM or email is fine. |
| D5 | Where the money is shown | A **"Server funded through: <Month YYYY>"** line, plus a monthly costs-vs-donations post | This makes "server duration" concrete and honest, and needs no payment API. |
| D6 | Surplus | Rolls forward into future months of hosting and API costs only | The page says this up front. |
| D7 | Shutdown | If the network shuts down, any unspent balance goes to the final hosting bills. No refunds after 30 days. | The page says this up front. PayPal/Stripe refunds within 30 days are handled on request. |
| D8 | Claude API spend | Donations **do not raise** the zero-cost-first spend cap on their own. Any cap increase is still Jeremy's call. | Matches the cost rule in core `docs/_project-context.md`. |

---

## 3. Only Jeremy can do these

**How the money actually flows (clarified 2026-09-15, Jeremy noticed the gap then closed it):**
Shockbyte's payment method was Stripe (card), not PayPal, so donations couldn't reach it directly.
**Fixed same day:** Jeremy switched Shockbyte's payment method to his **PayPal Debit Mastercard**,
which draws straight from the PayPal balance — so donations now flow directly into paying
Shockbyte, no manual bank-transfer step for that leg. This is exactly the "same account can also
pay vendors/invoices" property D1 was chosen for, now literally true for Shockbyte specifically.
The OVH VPS is still card-billed separately (not yet switched); until/unless that changes too,
covering it still means withdrawing PayPal balance to a bank/card, the same manual pattern
documented for the parked Venmo/Cash App plan (§7 V5).

1. **Monthly cost figures — resolved 2026-09-15:**
   - Game-server hosting (Shockbyte): **$24.99/mo, confirmed from the panel** (registered
     2026-09-02, monthly via Stripe). Corrects the $19.99 given verbally earlier — the panel
     figure is authoritative. **Next due date: October 2, 2026** — this is now the "funded
     through" value (§5), since no donations have been collected yet to extend it further.
   - OVH VPS (bots/APIs): **$10/mo, confirmed** — `aegis-services` `docs/ops/VPS.md`. Renews
     separately, next due 2026-10-13 (later than Shockbyte's, so it isn't the binding date).
   - Claude API: **no real metered spend exists to report.** Checked before asking Jeremy to
     decide: Claude Code usage (including the sessions doing this work) runs on his Max/Pro
     subscription seat, and Console usage/cost endpoints don't cover subscription seats at all
     (confirmed in MasterThread's own `tools/usage-monitor/README.md`); `core`'s
     `claude-review.yml` cost-tracking step (core#55) isn't actually posting cost comments on
     recent PRs (checked core #56/#60/#65/#67/#69 — none have one); no live player-facing bot
     uses a metered key yet (chat-monitor's README says outright "makes no Claude calls, costs
     nothing"; admin-bot/bug-report-agent aren't deployed). The one real metered spend on record
     predates all this — a since-retired test key burned its credits in a day on 2026-09-12 (19
     reviews, $0.46-$1.75 each). **Jeremy's call: use the pre-existing ~$15/mo planning estimate**
     from `aegis-services/docs/aegis-agent-orchestration-plan.md` (a pre-build projection for when
     admin-bot/bug-report-agent eventually run on real keys), labeled on the page as an estimate,
     not measured usage — revisit once a metered key actually goes live.
   - **Total: ~$49.99/mo**, now shown as a cost breakdown table on `/fund/` and in the Discord
     embed. **§3 item 1 is now fully resolved** — every figure and the funded-through date are
     real, nothing left `.tbc` here.
2. ~~Create/confirm a PayPal Business account... set the `paypal.me` handle~~ — **done 2026-09-15.**
   Jeremy created the PayPal Business account and a hosted donate button (`hosted_button_id=XRUFPV3ECAETC`).
3. **Decide whether donations and vendor payments share one balance or get separated by a labeled "Donations" tag/note in PayPal's transaction records** — needed so the monthly transparency post (Session 4) can tell donation income apart from other business activity on the same account.
4. **Approve the page and Discord copy** below.
5. **Discord:** create the `#fund-the-server` channel and a channel webhook. The plan uses a webhook, not an OAuth bot invite.

---

## 4. Sessions (one conversation, one PR each, per `session_plan_standard.md`)

### Session 1 — Policy (repo: `core`, docs only)
- Add a **"Donations"** subsection to `docs/_project-context.md`: donations only, zero counter-value, the D1–D8 defaults, and the rule "adding any perk or role requires Bohemia registration first."
- Update the status header of `site-chernarus/docs/nasdara-monetization-plan.md`: "Paid perks still paused; no-counter-value donations approved 2026-09-12 — see core `_project-context.md`." This is a separate small PR in site-chernarus.
- Check installed-mod licences for donation wording and record the result in `docs/mods/README.md` §4.
- **Done when:** the policy is merged and the mod-licence check is recorded, with a verdict for each installed mod.

### Session 2 — Website page (repo: `website`) — merged (PR #16, then #21 re-verify), real button wired 2026-09-15 (PR #27, open)
- Added `/fund/` (`src/pages/fund.html`, built via the site's `build.py` pipeline). Deployed and
  live since 2026-09-13 (`aegisdirective.net/fund/` returns 200).
- **2026-09-15:** PR #27 replaces the `.tbc` placeholder table with the real embedded PayPal
  `Donation.Button` widget (§2 D1), updates the "what the money is for" copy to three things
  (§ scope header above), and adds a real cost breakdown + funded-through date (§3 item 1) — no
  `.tbc` placeholders left in the content.
- **Done when:** PR #27 merged and redeployed (`wrangler deploy`). *Blocked on:* a pre-existing CI
  bug, not content — see the status header's PR #27 merge blocker note; needs
  `sudo systemctl restart aegis-gha-runner@website.service` (Jeremy) before it can merge.

### Session 3 — Discord (repo: `services`) — merged (PR #10), real link wired 2026-09-15 (branch pushed, PR queued)
- Added `scripts/post-fund-embed.mjs`, a one-shot script that posts and updates a pinned embed in
  `#fund-the-server` using the `DISCORD_WEBHOOK_FUND` secret — reuses the existing incoming-webhook
  pattern from CI notifications, no bot invite needed.
- **2026-09-15:** `agent/services/fund-embed-donate-link` swaps the old `PAYPAL_HANDLE`/`paypal.me`
  scheme for `PAYPAL_HOSTED_BUTTON_ID`, matching website PR #27, and collapses the four per-amount
  embed fields into one "Donate" field. Not yet opened as a PR — `services`' CLAUDE.md caps it at
  one open agent PR at a time and #93 was already open; open once #93 merges.
- **Correction to this plan:** pinning is not automatic. An incoming webhook cannot pin a message —
  only a bot with Manage Messages can. `docs/ops/FUND-EMBED.md` (in `services`) documents pinning
  by hand once, after the first post.
- Optional admin-bot `/fund` slash command noted in the doc, not built yet.
- **Done when:** merged, and Jeremy has created `#fund-the-server` + its webhook and set
  `DISCORD_WEBHOOK_FUND` (`gh secret set --repo yodatech1988/services --body <url>`), then the
  embed is posted, pinned by hand, and its links match the website.

### Session 4 — Monthly transparency routine (repo: `MasterThread`, checklist doc)
- A 5-minute monthly checklist: pull the PayPal donation total (per the labeling/tagging convention from §3 item 3, kept separate from vendor payments on the same account), subtract the hosting and API bills, update `status.json`, re-run the embed script, and post a one-line summary in `#fund-the-server` ("Sept: $X in, $Y hosting, $Z API → funded through Dec").
- **Later, not now:** PayPal IPN/webhook sent to a free Cloudflare Worker that updates `status.json` automatically. Build it only if the manual step gets skipped.

---

## 5. Draft copy

**Website `/fund/` and Discord embed (same text):**

> ### Keep the AEGIS servers running
> AEGIS is free to play and always will be. Donations pay for exactly three things:
> **the game-server hosting contract**, **the VPS that runs our Discord/server bots and APIs**,
> and **the AI (Claude API) that powers them.**
>
> **Donating gets you nothing in game.** No items, no perks, no queue priority, no roles. Not donating never limits anything.
>
> **[ $5 ]  [ $10 ]  [ $20 ]  [ Other ]**
>
> **Monthly costs:** Game-server hosting (Shockbyte) $24.99 · VPS (bots/APIs) $10.00 ·
> Claude API (estimate) ~$15.00 · **Total ~$49.99**
>
> **Server funded through: October 2, 2026** · the current hosting cycle's paid-through date, not
> a donation surplus (none collected yet) · updated monthly with a costs-vs-donations summary.
>
> Donations are one-time, go to the server operator personally, and are **not tax-deductible**.
> Any surplus pays for future months of hosting, infrastructure, and API costs. Refunds are
> available within 30 days on request.
>
> *AEGIS Directive is a community project, not affiliated with or authorized by Bohemia Interactive a.s.*

---

## 6. What would break this plan (revisit triggers)
- Anyone proposes a donor role, badge, name-in-game, or "thank-you" item → that's counter-value → Bohemia registration comes first (and the paused tiered plan should be un-paused properly instead).
- Bohemia changes its donation wording → re-check §1.
- Donations routinely exceed costs → decide publicly what surplus funds (for example, a second site's hosting) before accepting more. Don't let it build up quietly.

---

## 7. Backlog — Venmo and Cash App (PARKED until there's a real player base)

**Status:** parked 2026-09-14, Jeremy's call. **Priority: P3 (deferred)** per
`standards/sessions/priority_classification.md`. No sessions get dispatched, no accounts get created,
and no placeholder links get added to `/fund/` or the Discord embed until the unpark trigger below is
met. Do not let this silently drop — carry it in handoffs as parked, not forgotten.

### Goal
Let donors who don't use PayPal give through **Venmo** and/or **Cash App**, with every public-facing
name showing **"AEGIS Directive"**, not Jeremy's personal name. Same rules as the rest of this plan:
one-time, zero counter-value, same $5/$10/$20/Other amounts.

### Unpark trigger
Revisit when there's a real player base. Default measurable version (Jeremy can change it):
- **PayPal donations are actually coming in** (the `/fund/` page is deployed with real links), **and**
- either a sustained active player base (roughly 20+ unique players a week for a month), **or** at
  least two players ask for a non-PayPal way to donate.

The monthly transparency routine (Session 4) and every new site/map launch (the REPOS.md monetization
standing rule) are the two points where someone checks this trigger.

### What "anonymous" means here (set expectations up front)
- **Operator side:** public-facing names can be "AEGIS Directive" on all three platforms. Each platform
  still holds Jeremy's legal name/SSN for identity checks and tax reporting, and donations remain
  taxable income (§1 Taxes). Hidden from the public, not from the platforms or the IRS.
- **Donor side:** there is no truly anonymous path. Jeremy sees the donor's account name, and donors can
  use a nickname display name and keep payments private. Never publish donor names (D4).

### Decisions (defaulted)
| # | Decision | Default | Why |
|---|---|---|---|
| V1 | PayPal public name | Set PayPal's business display name to **"AEGIS Directive"** — do this even before unparking, when the PayPal Business account is set up (§3 item 2) | Cheap, and the same "no personal name" goal applies to PayPal today |
| V2 | First extra platform | **Venmo Business profile** named "AEGIS Directive" (~1.9% + $0.10 per payment) | Cheapest, widely used, and owned by PayPal. **Never** take donations on a personal Venmo (against Venmo's rules, shows the real name, payments can default to public) |
| V3 | Cash App | **Only if players ask for it.** Cash App for Business, `$AEGISDirective`-style cashtag (2.75% per payment) | Highest fee, and a third balance to reconcile |
| V4 | Where the money lands | **PayPal stays the main account** — it pays hosting/API and is the only balance the "funded through" line counts | One place to pay bills from and one number to report |
| V5 | Moving money | Once a month, move the Venmo/Cash App balances to the linked bank, then into PayPal, as part of the Session 4 routine. Tag each transfer "Donations" | Venmo and Cash App can't transfer into PayPal directly |
| V6 | Minimum | Same **$3** "Other" minimum on every platform | Consistency with D3 |
| V7 | Re-check fees | Confirm current Venmo Business / Cash App for Business fees and ToS on the day this unparks — the figures above are as of 2026-09-14 | Fees and rules change |

### Owner-only steps (when unparked)
1. Create the Venmo Business profile (and Cash App for Business, if V3 applies), named "AEGIS Directive".
2. Link the same bank account used by PayPal, and send me the Venmo handle / cashtag. Handles aren't secrets, so they can go in a plain message.
3. Approve the updated `/fund/` and Discord embed copy.

### Sessions (when unparked — one PR each)
- **V-Session 1 (this repo):** amend this plan — lift the parked status, record the handles and
  confirmed fees, and extend the Session 4 monthly checklist with the Venmo/Cash App totals and the
  bank → PayPal transfer step. *Done when:* merged.
- **V-Session 2 (`website`):** add Venmo (and Cash App if V3) buttons to `/fund/` under the PayPal
  buttons, same amounts, with a one-line fee note. *Done when:* merged and deployed, and the links open
  the right profiles.
- **V-Session 3 (`services`):** add optional `VENMO_HANDLE` / `CASHAPP_TAG` env vars to
  `scripts/post-fund-embed.mjs` (unset renders nothing, not "TBC"), and update `docs/ops/FUND-EMBED.md`.
  *Done when:* merged, embed re-posted and re-pinned, links match the website.

### Risks
- **Reconciliation drift:** three balances make the monthly post easy to get wrong. If the monthly routine
  starts getting skipped, drop Cash App first.
- **Counter-value creep:** the same §6 triggers apply. A "thanks for the Venmo!" shout-out naming the
  donor is fine privately, never publicly.

*Not legal or tax advice.*
