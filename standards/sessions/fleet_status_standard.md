# Fleet Status standard

Companion to [`decision_queue_standard.md`](decision_queue_standard.md) — same pack, same night,
same reason for existing: durable in git for a session that inherits the fleet without this
conversation's context.

**Current URL:** https://claude.ai/artifact/AAiVG3MxK1r3yNgm8tzMmf

**Sibling artifacts:** Ops Decision Queue (https://claude.ai/artifact/1fMqNA1zdQKsq1FDEFvyzf) and
Ops Roster (https://claude.ai/artifact/U23uudrKWTT1RJ8rrews4N), cross-linked via each page's
`nav.pack` bar.

## Platform constraint: one database per artifact

Each of the three artifacts above has its **own separate database** — the artifact platform gives
one store per artifact, with no built-in way for one to read another's. Fleet Status and the
Decision Queue are two different databases even though they're both "the dashboard" in casual
conversation. A true single unified store would mean merging the two artifacts into one, which
**Jeremy explicitly declined** on 2026-09-16: two separate, live-updating artifacts on the existing
infrastructure is the accepted shape. Don't propose or build a merge without a fresh, explicit ask.

## Panel liveness — what's real, what isn't, what breaks on rotation

Every panel subscribes via the db capability's `onSnapshot`, so the **transport** is live
everywhere: a write reaches every open view within about a second. That is not the same claim as
"this panel reflects current reality," which depends on whether anything is actually writing to it.

| Panel | Transport | Has an active writer? |
|---|---|---|
| `sessions` (teams table, risk banner, wind-down banner) | live | Any active session writes its own doc. Survives fleet rotation — a new session just needs to know to self-report here. |
| `goals` / `tasks` (93-task work tree) | live | No continuous writer. Updates instantly when someone edits a task doc, but nothing does that on a schedule. |
| `blocked`, `health` | live | Event-driven, written when something worth flagging happens. Same as above — live mechanism, manual cadence. |
| `costs` | live | Same — each row shows its own "Checked" timestamp because there's no polling writer. |
| `usage` | live | Same — the panel says explicitly it's a point-in-time spot-check, not a meter. |
| `queue`, `prs` (merge queue / open PRs) | live | **Hard dependency on one specific session.** As of 2026-09-16, github-8e is the sole writer of `queue`, keeping it synced to their own `merge-queue.json`. `prs` was seeded from a one-time sweep and has no confirmed continuous writer at all. |

**The one thing a fresh session must know immediately:** the `queue` panel's liveness is not
structural — it exists only because github-8e is actively choosing to keep writing it. **If that
seat doesn't survive the fleet's consolidation/rotation, `queue` freezes silently.** The page has no
mechanism to detect "my writer stopped existing" — a frozen `queue` panel looks identical to a
current one until someone checks the timestamps by hand. If github-8e's seat changes, either get the
new equivalent seat writing `queue` the same way, or explicitly mark the panel as no-longer-maintained
rather than let it sit there looking current. This is the single highest-priority fact in this
document.

## Display mode

Append `?wallboard=1` to the Fleet Status URL (or use the display-mode toggle link in its nav bar)
for a large-type, distance-readable layout intended for a permanent second monitor: wind-down/risk/
blocked panels promoted and enlarged, everything else still present and still live but visually
quieter, reference/footer copy hidden. A companion launcher,
`C:\Users\yoda_\GitHub\AEGIS-Fleet-Wallboard.cmd`, opens it in an app-mode browser window (no tabs,
no address bar) maximized, with a one-time on-screen note to drag it to the second monitor — it
can't safely guess monitor layout, so it doesn't hardcode window coordinates. Matches the existing
double-click-script convention (`AEGIS-*.cmd` at the `GitHub\` root) rather than handing Jeremy a
terminal step.

A true kiosk variant (Chrome `--kiosk`, resists being covered, harder to exit) was sketched but not
built — real tradeoff (claims the whole monitor, stickier to exit) that needs Jeremy confirming the
appetite for it specifically before anyone builds it.

## Change signal

Any panel whose underlying data actually changes pulses once (a brief colored glow around its
border, ~2.4s, respects `prefers-reduced-motion`) so a change landing while attention is on another
screen is still noticeable on return — not just correct in the DOM. No pulse on first load, only on
a genuine change afterward. Implemented as a per-panel signature comparison
(`flashIfChanged` in the page's script), not per-row — cheap, and sufficient for "did something in
this panel change," which is the actual question at a glance.
