# Household: connecting a second Claude account (spouse)

Written 2026-09-23 at the owner's request. **Status: parked in the big-picture plan (owner,
2026-09-23: "make this a part of our big picture plans, but don't worry about building it this
moment").** Nothing here is built or scheduled; the owner decisions below stay open until the work
is picked up. Listed in `docs/ROADMAP.md` (Later) and `docs/WORKSTREAMS.md` (Household).
Checked against ops-household `main` at `89deba2` (`docs/PLAN.md`,
`docs/PHASE-5-SCOPE.md`, `docs/DATA-MODEL.md`, `docs/CONSENT-NOTE.md`).

## What was asked

Jeremy's wife has her own, separate Claude account. She should be able to work with the household
system in two areas:

1. **Food and nutrition.** She runs this for the household.
2. **The son's care plan.** She needs to be able to add to it.

The owner picked the **private household Discord server** as the channel between the two accounts.

## How two Claude accounts can talk at all

Claude sessions, `SendMessage`, Routines and connectors all belong to one account. Her Claude cannot
message, wake or read Jeremy's sessions, and his cannot reach hers. They can only meet on a surface
both can reach. Here that surface is the household Discord server:

```
her Claude app ──(she posts, or her own Discord connector)──▶ household Discord ◀── household bot
                                                                                     │ (plain code,
                                                                                     ▼  via gateway)
                                                                        ops-household store ──▶ Jeremy's sessions
```

- **She is a guardian row.** `guardians` already fits her: `relationship = parent`, her own
  `discord_user_id`, her own `google_calendar_id`, her own consent acknowledgement. No schema change.
- **Her Claude never gets a credential of Jeremy's.** She posts in Discord herself, or her own Claude
  posts for her through a Discord connector on *her* account. Jeremy's system reads the channel through
  the household bot. The bot holds no model and follows the gateway rule in ops-household `PLAN.md`
  Contracts.
- **Nothing a Discord post says is an instruction to a session.** A post becomes a *proposed* item
  (same rule as the Session 5 suggestion agent: it proposes, a deterministic rule or a guardian
  approves). This also keeps a compromised Discord account from steering the fleet.

## Conflicts with rules already in force

These are why this is a proposal and not a build.

1. **The care plan is D3, and the design has no place to put it on purpose.** `DATA-MODEL.md` makes
   anything about a minor beyond `first_name` D3. The `minors` table has no column for it, and no model
   call can reach it. A care plan (health, therapy, medication, school supports) is exactly that
   data. The rule is enforced by the schema, and changing it needs owner review under CODEOWNERS.
2. **Discord is title-only.** `send_discord_reminder(title, recipient)` has no detail parameter, and a
   denylist blocks health terms at write time. Care-plan *content* cannot go over Discord either way.
   Only a title like "[name]: care plan review Thu" can.
3. **Food and nutrition is not in Phase 5 scope.** Phase 5 covers profiles, calendar, reminders,
   suggestions and deletion. Meal plans and shopping lists would be a new module. The son's dietary
   restrictions or allergies count as health data about a minor (D3), just like (1).
4. **Timing.** The household Discord server does not exist yet (owner step, `PHASE-5-SCOPE.md` §3a
   item 1). On 2026-09-21 the owner put Phase 5 after the Phase 7 review, so no gateway or
   live-host work before mid-October at the earliest.

## Proposed shape

| Area | Over Discord | Where the real content lives | Model access |
|---|---|---|---|
| Meals and groceries (adult-level) | `#meals` channel: she posts the plan or list, the bot turns items into proposals. Reminders stay title-only ("Grocery run 5pm") | New `meal_plan` and `shopping_list` tables in ops-household (D1/D2, adult data only) | Yes. Suggestion agent may read them, same read-only allowlist pattern |
| Son's dietary needs and allergies | Never | With the care plan (row below) | No |
| Son's care plan | Only title-only prompts, e.g. "[name]: care plan updated", "[name]: review Thu" | **Option A (recommended now):** a document shared between the two of you outside this system (e.g. a shared Google Doc or a private Notion page). The system stores a pointer only, never the content. **Option B (later):** a D3 store on the vault host with passkey release, per the authority doc's D3 rule | A: none. B: deterministic code only, never a model |

Option A works as soon as the document is shared, with no schema change and no D3 build. It fits
the design's rule that the system knows only what reminders need. Option B is a real build and depends
on the vault host, the gateway and a schema change, so it only makes sense if you want the system
itself to act on care-plan content.

## Owner decisions

1. **Care plan storage:** A (shared doc outside the system, pointer only) or B (D3 vault store,
   a later build). Recommendation: A.
2. **Food and nutrition module:** add it to ops-household as a new session (meal plan and shopping
   list tables, `#meals` channel intake), scheduled with the rest of Phase 5. Recommendation: yes,
   adult data only; the son's dietary needs follow decision 1.
3. **Her Claude posting to Discord:** she posts herself, or her own Claude posts through a Discord
   connector on her account. Recommendation: start with her posting herself, and add a connector on
   her account only if she wants it. Either way, no credential of Jeremy's goes to her account.
4. **Timing:** keep this behind the Phase 7 review with the rest of Phase 5, or pull the Discord
   server creation forward. Recommendation: pull creating the server and inviting her forward (owner
   clicks, no code). Leave the bot and gateway work where it is scheduled.
5. **Consent:** she gets the adult consent note (`CONSENT-NOTE.md`, v1) and, as a guardian, acks the
   child note for the son. If the meals module lands, the adult note needs a line about meal data, and
   the version gets bumped so consent is asked again.

## What she does, once decided

1. Joins the private household Discord server (Jeremy invites her; it is not the AEGIS server or the
   PM's server).
2. Reads the consent note, and Jeremy records it with `tools/ack_consent.py` once 5.1 is deployed.
3. Posts meal plans and grocery items in `#meals`.
4. Edits the care plan in the shared document (option A). The system pings both of you with
   title-only reminders.
