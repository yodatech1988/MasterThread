# AEGIS Directive — Server Operating Donations Plan

**Status:** draft for Jeremy's approval · 2026-09-12
**Scope:** one-time donations of **$5 / $10 / $20 / Other**, shown on aegisdirective.net and the AEGIS Discord.
**What the money is for:** only (1) the game-server hosting contract and (2) Claude API tokens that run the network's agents.
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
| D1 | Platform | **Ko-fi, one-time donations only** (memberships/tiers off) | This was the platform already chosen before the pause. Ko-fi takes 0% on donations; Stripe/PayPal processing fees still apply. It needs no backend and supports custom amounts. **Fallback:** four Stripe Payment Links (three fixed amounts plus one "customer chooses"), if Ko-fi can't show $5/$10/$20 presets cleanly. |
| D2 | Recurring monthly option | **Off at launch** | A monthly option reads like a subscription, and subscribers expect something back. It can be added later as "monthly, still no benefit." |
| D3 | "Other" minimum | **$2** | Below about $2, the ~$0.30 processing fee eats too much of the gift. |
| D4 | Discord role / donor wall | **None** | This keeps the "no counter-value" position clean. A private thank-you DM or email from Ko-fi is fine. |
| D5 | Where the money is shown | A **"Server funded through: <Month YYYY>"** line, plus a monthly costs-vs-donations post | This makes "server duration" concrete and honest, and needs no payment API. |
| D6 | Surplus | Rolls forward into future months of hosting and API costs only | The page says this up front. |
| D7 | Shutdown | If the network shuts down, any unspent balance goes to the final hosting bills. No refunds after 30 days. | The page says this up front. Ko-fi/Stripe refunds within 30 days are handled on request. |
| D8 | Claude API spend | Donations **do not raise** the zero-cost-first spend cap on their own. Any cap increase is still Jeremy's call. | Matches the cost rule in core `docs/_project-context.md`. |

---

## 3. Only Jeremy can do these

1. **Monthly cost figures:** the hosting contract amount and renewal date, and the Claude API monthly cap. These feed the "funded through" line.
2. **Create the Ko-fi account:** turn off memberships and shop, set a $5 coffee price so presets are 1/2/4 coffees, and turn on custom amounts.
3. **Connect the payout** (Stripe or PayPal) in Jeremy's name.
4. **Approve the page and Discord copy** below.
5. **Discord:** create the `#fund-the-server` channel and a channel webhook. The plan uses a webhook, not an OAuth bot invite.

---

## 4. Sessions (one conversation, one PR each, per `session_plan_standard.md`)

### Session 1 — Policy (repo: `core`, docs only)
- Add a **"Donations"** subsection to `docs/_project-context.md`: donations only, zero counter-value, the D1–D8 defaults, and the rule "adding any perk or role requires Bohemia registration first."
- Update the status header of `site-chernarus/docs/nasdara-monetization-plan.md`: "Paid perks still paused; no-counter-value donations approved 2026-09-12 — see core `_project-context.md`." This is a separate small PR in site-chernarus.
- Check installed-mod licences for donation wording and record the result in `docs/mods/README.md` §4.
- **Done when:** the policy is merged and the mod-licence check is recorded, with a verdict for each installed mod.

### Session 2 — Website page (repo: `website`)
- Add a new page, `public/fund/index.html`. Per `aegis-website-build.md`, monetization comes back only "as its own page and its own decision," and this is that page.
- The page has four buttons ($5, $10, $20, Other) linking to Ko-fi, or to the Stripe Payment Links if the fallback was chosen. It is plain HTML with no embedded third-party widget, so the Content Security Policy stays simple and there's no tracking.
- The "Server funded through" line reads from a static `public/fund/status.json` (`{ "fundedThrough": "2026-12", "updated": "2026-09-12" }`) that is edited by hand monthly.
- Add a quiet "Fund the server" footer link on every page. No pop-ups, and nothing on the join/start flow that suggests paying.
- Update `aegis-website-build.md` so it no longer says "no monetization page exists."
- **Done when:** `wrangler dev` renders the page, all four links resolve, the disclaimer is in the footer, and the page passes the phone-width check.
- *Blocked on:* the website has never been deployed (REPOS.md: Cloudflare connector auth, #3). The page can merge before deploy.

### Session 3 — Discord (repo: `services`)
- Add a one-shot script, `scripts/post-fund-embed`, that posts and updates the pinned embed in `#fund-the-server` using the `DISCORD_WEBHOOK_FUND` secret. This reuses the existing incoming-webhook pattern, so it adds no bot and no Ko-fi bot.
- Optional: an admin-bot `/fund` slash command that replies only to the person who ran it, with the same four links. admin-bot is the only live agent, so this is low risk.
- **Done when:** the embed is posted and pinned, and the links match the website.

### Session 4 — Monthly transparency routine (repo: `MasterThread`, checklist doc)
- A 5-minute monthly checklist: pull the Ko-fi total, subtract the hosting and API bills, update `status.json`, re-run the embed script, and post a one-line summary in `#fund-the-server` ("Sept: $X in, $Y hosting, $Z API → funded through Dec").
- **Later, not now:** a Ko-fi webhook sent to a free Cloudflare Worker that updates `status.json` automatically. Build it only if the manual step gets skipped.

---

## 5. Draft copy

**Website `/fund/` and Discord embed (same text):**

> ### Keep the AEGIS servers running
> AEGIS is free to play and always will be. Donations pay for exactly two things:
> **the game-server hosting contract** and **the AI (Claude API) that runs our Discord and server agents.**
>
> **Donating gets you nothing in game.** No items, no perks, no queue priority, no roles. Not donating never limits anything.
>
> **[ $5 ]  [ $10 ]  [ $20 ]  [ Other ]**
>
> **Server funded through: December 2026** · updated monthly with a costs-vs-donations summary.
>
> Donations are one-time, go to the server operator personally, and are **not tax-deductible**.
> Any surplus pays for future months of hosting and API costs. Refunds are available within 30 days on request.
>
> *AEGIS Directive is a community project, not affiliated with or authorized by Bohemia Interactive a.s.*

---

## 6. What would break this plan (revisit triggers)
- Anyone proposes a donor role, badge, name-in-game, or "thank-you" item → that's counter-value → Bohemia registration comes first (and the paused tiered plan should be un-paused properly instead).
- Bohemia changes its donation wording → re-check §1.
- Donations routinely exceed costs → decide publicly what surplus funds (for example, a second site's hosting) before accepting more. Don't let it build up quietly.

*Not legal or tax advice.*
