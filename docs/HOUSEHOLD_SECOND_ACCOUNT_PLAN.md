# Plan: Household second account (spouse), meals and care plan

Follows MasterThread `standards/sessions/session_plan_standard.md`. Do one session per fresh
conversation, opened in its own worktree of **ops-household** (standard rule 9). All build sessions
(H1-H5) land in ops-household. This file is their home until the work is picked up (see "Moving
this plan").

**Status: parked (owner, 2026-09-23: "make this a part of our big picture plans, but don't worry
about building it this moment").** Nothing here is built or scheduled. Listed in `docs/ROADMAP.md`
(Later) and `docs/WORKSTREAMS.md` (Household). Written against ops-household `main` at `89deba2`
(`docs/PLAN.md`, `docs/PHASE-5-SCOPE.md`, `docs/DATA-MODEL.md`, `docs/CONSENT-NOTE.md`). Re-check
those before starting any session. Session numbers use an `H` prefix so they don't clash with
ops-household's own Sessions 1-6.

## Target (settled)

Jeremy's wife has her own, separate Claude account. She handles food and nutrition for the household,
and she needs to be able to add to the son's care plan. The owner chose the **private household
Discord server** as the channel between the two accounts.

```
her Claude app ──(she posts, or her own Discord connector)──▶ household Discord ◀── household bot
                                                                                     │ (plain code,
                                                                                     ▼  via gateway)
                                                                        ops-household store ──▶ Jeremy's sessions
```

Done looks like this:

- She is a `guardians` row (`relationship = parent`) with her own Discord ID, calendar and consent ack.
- She posts meal plans and grocery items in `#meals`. They arrive as **proposals** that a guardian
  approves, and approved items drive title-only reminders.
- The care plan's content lives **outside the system** in a document shared between the two parents
  (decision D1). The system only sends title-only review and update prompts.
- None of Jeremy's credentials are on her account, and no Discord post is ever treated as an
  instruction to a session.

**Why two Claude accounts can't simply talk:** sessions, `SendMessage`, Routines and connectors
belong to one account. Her Claude cannot message, wake or read Jeremy's sessions, and his cannot
reach hers. They can only meet on a surface both can reach. Here that surface is the Discord server.

## Rules already in force that shape this plan

1. **The care plan is D3.** ops-household `DATA-MODEL.md` makes anything about a minor beyond
   `first_name` D3. `minors` has no column for it on purpose, and no model call can reach it.
   Changing that is a CODEOWNERS-reviewed schema change.
2. **Discord is title-only.** `send_discord_reminder(title, recipient)` has no detail parameter, and a
   write-time denylist blocks health terms. Care-plan content cannot go over Discord.
3. **Food and nutrition is outside Phase 5's scope.** It is a new module. The son's allergies and
   dietary needs are D3 like (1), so they are never stored in the meals tables.
4. **Timing.** Phase 5 runs after the Phase 7 review (owner, 2026-09-21), so it can't start before
   mid-October. The household Discord server doesn't exist yet.

## Backlog first

- **Phase 5 dependencies this plan rides on.** H3 needs ops-household Session 4 (dispatcher). H4
  needs Sessions 4 and 5 (promotion boundary) and the Phase 2 gateway (2.31). None has started
  (`PHASE-5-SCOPE.md` §2).
- **One open agent PR per ops-household** (standard rule 4), so H1-H5 run in sequence, interleaved
  with Phase 5's own sessions.

## Open decisions (default in force until the owner decides)

- **D1. Care plan storage:** default **A: a document shared between the parents outside the system**
  (a shared Google Doc or private Notion page), with no pointer or content stored in ops-household.
  Alternative B is a D3 store on the vault host with passkey release. It needs a vault deploy, the
  gateway and a CODEOWNERS schema change, and is only worth it if the system itself must act on
  care-plan content. B is not planned below. Choosing it adds a session H6.
- **D2. How she posts:** default **she posts in Discord herself**. A Discord connector on *her*
  Claude account is her choice to add later, needs no change here, and never uses Jeremy's
  credentials.
- **D3. Shopping list back to Discord:** default **no**. Reminders stay title-only ("Grocery run
  5pm"), and she reads the list where she wrote it. A yes adds a second sender with its own planted
  test suite (H5).
- **D4. Timing:** default **Stage 0 owner steps may happen any time. H1-H2 are repo-local and can run
  whenever ops-household has idle capacity. H3-H5 follow their Phase 5 dependencies.** The
  alternative is holding everything, including Stage 0, until Phase 5 starts.
- **D5. Consent re-ask:** default **bump the adult note to v2 when H1 lands**, so everyone
  (Jeremy included) re-acknowledges once the system stores meal data.

## Contracts

- **Meals tables are adult-only.** `meal_plan` and `shopping_list_item` have no FK to `minors` and no
  free-text column beyond an item name (varchar 80). A per-child dietary note is D3 and is never
  stored there (rule 3). The schema-vs-doc test enforces the column list.
- **Discord intake is proposal-only.** Every inbound `#meals` message becomes a `propose_suggestion`
  row (ops-household `PLAN.md` Contracts) with a new `kind = meal_item | shopping_item`. Only a
  guardian's explicit approval (a reaction or command by a known `guardians.discord_user_id`) promotes
  it. Messages from anyone not in `guardians` are dropped and logged. Message text is never passed to a
  session as a prompt.
- **Care-plan prompts use a neutral title.** The template is `"<first_name>: plan review"` and
  `"<first_name>: plan updated"`. It must pass the existing denylist unchanged (no health words), and
  a planted test keeps it that way.
- **Inbound Discord reads go through the gateway**, the same as outbound (`PLAN.md` Contracts). If
  2.27 lands with an outbound-only shape, H4 stops and the contract gets fixed first.

---

## Stage 0: Owner steps (no code, any time under D4)

- **You:**
  1. Create the private household Discord server and invite the bot. This is ops-household
     `PHASE-5-SCOPE.md` §3a item 1, and it is a separate server from AEGIS and the PM's server.
  2. Invite her, and create `#meals` and a general channel.
  3. Create the shared care-plan document and share it with her (D1 option A).
  4. Give her the adult consent note, and as a guardian she acknowledges the child note for the son.
     `ack_consent.py` records both once 5.1 is deployed. Until then, record the date by hand.
- **Done when:** she is in the server, the care-plan document is shared, and she has read the note.

## Session H1: Meals data model

- **Read:** ops-household `docs/DATA-MODEL.md`, `migrations/`, `tests/test_schema.py`, this plan's
  Contracts.
- **Do:** Add `meal_plan` (`meal_id`, `planned_for` date, `slot` enum breakfast/lunch/dinner/snack,
  `title` varchar 80, `author_member_id` FK `guardians`, timestamps) and `shopping_list_item`
  (`item_id`, `name` varchar 80, `status` enum open/bought, `author_member_id`, timestamps) as
  migration `0003`. Give each column a data class and justification row in `DATA-MODEL.md`. Follow
  whatever delete behaviour the owner chose for the existing tables (`delete_person.py` is dry-run only
  and the cascade choice is pending, per decision-ops-household-right-to-delete-schema-2026-09-19). Do
  not choose it here. Extend the dry-run test so it reports one seeded row in each new table.
- **Out of scope:** intake, reminders, any child-related field.
- **Done when:** the schema-vs-doc test passes with the new rows, the delete dry run lists the
  seeded meals rows, and no column references `minors`.
- **Model:** Sonnet 5, medium.
- **Starter prompt:** `Read MasterThread docs/HOUSEHOLD_SECOND_ACCOUNT_PLAN.md Session H1 and Contracts only, then ops-household docs/DATA-MODEL.md. Add the meals tables as migration 0003 with their DATA-MODEL rows and delete-drill coverage.`

## Session H2: Consent note v2

- **Read:** ops-household `docs/CONSENT-NOTE.md`, `tools/consent_lib.py`, this plan's D5.
- **Do:** Add a plain-language line about meal plans and shopping lists to the adult note. Add one
  sentence saying care-plan details stay in a document outside the system and the system only sends
  "plan review" reminders. Bump to `v2`. Extend the consent test so a v1 ack reads as stale.
- **Done when:** `check_consent_complete.py` reports v1 acks as incomplete in the fixture test.
- **Model:** Sonnet 5, low.
- **Starter prompt:** `Read MasterThread docs/HOUSEHOLD_SECOND_ACCOUNT_PLAN.md Session H2 only and ops-household docs/CONSENT-NOTE.md. Update the adult note for meal data and bump it to v2.`

## Session H3: Care-plan review prompts

- **Read:** this plan's Contracts (neutral title), ops-household Session 4's dispatcher and
  `tests/test_reminder_title_safety.py`.
- **Do:** Add a recurring reminder rule that inserts `"<first_name>: plan review"` into
  `reminder_queue` for both guardians on a schedule set per household (default monthly). Add planted
  cases to show that the template passes and that a detail-bearing variant is rejected.
- **Out of scope:** any link to the care-plan document or any of its content.
- **Trigger to start:** ops-household Session 4 merged.
- **Done when:** a fixture run queues the reminder for both guardians, and the planted cases pass.
- **Model:** Sonnet 5, low.

## Session H4: `#meals` intake

- **Read:** this plan's Contracts (proposal-only, gateway inbound), ops-household Session 5's
  `propose_suggestion` shape and promotion boundary.
- **Do:** Build the deterministic intake. It reads `#meals` through the gateway stub, drops senders
  not in `guardians`, and parses one item per line into `propose_suggestion` rows (`kind` meal_item or
  shopping_item). A guardian's approval promotes them into `meal_plan` or `shopping_list_item`. Planted
  tests cover a non-guardian sender, a prompt-injection-shaped message, and an over-length item.
- **Out of scope:** real Discord calls until the gateway exists, and any model parsing (Session 5's
  router wiring is still pending).
- **Trigger to start:** ops-household Sessions 4 and 5 merged, and the gateway contract confirmed to
  cover inbound reads.
- **Done when:** an intake message can reach the meals tables only through promotion, and every
  planted case is rejected or dropped.
- **Model:** Sonnet 5, medium.

## Session H5: Meal reminders (plus shopping list sender only if D3 = yes)

- **Do:** Approved `meal_plan` rows with a prep time generate title-only reminders ("Dinner prep
  5pm"). If D3 is yes: add `send_shopping_list(items: list[str], recipient)` with its own length cap,
  denylist and planted suite. It is a separate function; the reminder sender stays untouched.
- **Trigger to start:** H4 merged.
- **Done when:** a fixture meal produces one title-only reminder. Under D3 = yes, the shopping list
  sender's planted suite also passes.
- **Model:** Sonnet 5, medium.

## Moving this plan

When the work is picked up, copy Sessions H1-H5 and Contracts into ops-household `docs/PLAN.md` in
that repo's first H-session PR. Update the ops-household row in `docs/REPOS.md`, and replace this file's
body with a pointer.

---

## Status

| Session | PR | State |
|---|---|---|
| Stage 0 (owner) | | not started, owner steps |
| H1 meals data model | | parked, repo-local, no blocker once picked up |
| H2 consent note v2 | | parked, runs with or right after H1 |
| H3 care-plan prompts | | parked, waits on ops-household Session 4 |
| H4 `#meals` intake | | parked, waits on Sessions 4 and 5 plus gateway |
| H5 meal reminders | | parked, waits on H4 |
