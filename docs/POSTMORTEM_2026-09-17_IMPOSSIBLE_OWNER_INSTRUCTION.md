# Postmortem: an owner instruction that could not be carried out

## Summary

- **Incident ID:** PM-2026-09-17-01
- **Date/time:** filed 2026-09-17T22:30:06Z, detected 22:45:25Z, corrected 22:55:59Z. Roughly 15
  minutes live, of which the owner spent an unknown part trying to act on it.
- **Impact summary:** An Ops Decision Queue action card instructed the owner to create a Cloudflare
  tunnel in the Cloudflare dashboard. The dashboard cannot create the kind of tunnel the code needs.
  The instruction was impossible as written, was relayed to the owner a second time as a live
  walkthrough, and was read by three sessions without anyone noticing. **No production impact, no
  host touched, no credential exposed, nothing applied.** The cost was the owner's time and the
  quiet erosion of his ability to trust a card. The near-miss is larger than the incident: had he
  been more confident, he would have created the wrong kind of tunnel, been handed a credential the
  vault cannot consume, and the error would have surfaced at apply time on the host that is
  scheduled to become the only way in.

This postmortem is written for sessions and for the owner, including people who were not present.
It assumes no memory of the evening.

## Timeline

All times UTC. Timestamps marked **[store]** were read from the Decision Queue database, not typed
from memory; those marked **[clock]** were read from `date -u` at the moment of the action. One
entry has no independent timestamp and says so.

| Time | Event |
|---|---|
| 22:30:06 **[clock]** | `github-29` files action card `action-cloudflare-vault-tunnel-dashboard-2026-09-17`. Step 2 tells the owner to create the vault's tunnel in the Cloudflare dashboard under `Zero Trust > Networks > Tunnels`. |
| 22:30:45 **[store]** | Card confirmed landed by reading it back. The read-back checked that the card *existed*, not that it was *correct*. |
| unknown | `github-c5` (PM) walks the owner through steps 2–5 of the card in chat, relaying the path verbatim. Reported by the PM; no independent timestamp available. |
| 22:42:52 **[store]** | Owner resolves the service-token decision. |
| 22:42:54 **[store]** | Owner resolves the credential-location decision. |
| 22:43:15 **[store]** | Owner merges ops-infra PR #20, which contains the `cloudflared` role the card was meant to feed. |
| 22:45:25 **[store]** | Owner presses **I did it – check it** on the dashboard card with the comment: *"I don't know how to do this, I will need guided in session."* This is the detection event. |
| ~22:52 | `github-29` reads the claim, treats the comment as a report rather than a completion, and goes to write better guidance. |
| ~22:54 | While sourcing accurate dashboard navigation from Cloudflare's own documentation, `github-29` finds that a locally-managed tunnel — the kind the merged role requires — cannot be created from the dashboard at all. |
| 22:55:59 **[clock]** | Card rewritten: status held open, `checkedBy: owner`, `checkResult` recording that the error was in the instruction and not in anything the owner did. |
| ~22:58 | PM independently verifies the defect against `origin/main` rather than relaying it, and confirms. |

## Root cause

### Technical

The `cloudflared` role merged in ops-infra #20 is built for a **locally-managed** tunnel. Its
template writes a `config.yml` carrying `tunnel:`, `credentials-file:` and the ingress rules, and
its systemd unit runs `cloudflared --config <file> tunnel run`. That shape consumes a credentials
JSON file.

The Cloudflare dashboard creates **remotely-managed** tunnels. Those store their configuration at
Cloudflare and hand back a *token*, consumed as `tunnel run --token <TOKEN>`. The unit never passes
`--token` and would not use one. Per Cloudflare's own documentation, a locally-managed tunnel is
created only through `cloudflared tunnel login` and `cloudflared tunnel create` on the command line.

So the card asked the owner to visit a screen that cannot produce the artifact the code consumes.
A second, smaller error in the same step: the navigation path had moved to `Networking > Tunnels`,
so even the screen name was stale.

### Organizational — the actual root cause

The same pull request verified its machine-facing facts to an unusually high standard and its
human-facing instructions to essentially none.

In #20, `github-29` confirmed that `cloudflared` is absent from Ubuntu by querying Launchpad's API
across four series; pinned the APT signing key by full fingerprint read from the key itself; pinned
the package version; and confirmed the `.deb` checksum was byte-identical across two independent
distribution paths. It validated the rendered tunnel config by running `cloudflared tunnel ingress
validate` against it. It ran the guard test suite rather than asserting it passed, and that caught
two real defects.

The same session then wrote a five-step procedure for a human being from an unchecked mental model
of a web UI, and did not test a single step of it.

The split was not laziness. It was a **category error about what counts as a claim.** Facts
addressed to a machine were treated as claims requiring evidence. Instructions addressed to a person
were treated as prose. They are both claims, and the instruction is the one with a human on the
other end of it.

### Why three readers missed it

`github-29` wrote the card, `github-c5` read it closely enough to walk the owner through it line by
line, and `github-b6` and `github-38` both read it as a dependency of their own lanes. None caught
it, because all four were asking **"would he understand this?"** — and it read perfectly clearly. It
was well-structured, it named the screens, it explained the reasoning, and it said what he would
see. Clarity review cannot detect an instruction that is lucid and impossible.

Nobody asked **"can this actually be carried out?"**, which requires either performing the steps or
checking that each named artifact exists and produces what the next step consumes.

### Detection

The owner said he did not know how. That is the only reason this was caught before the apply.

This deserves emphasis because it inverts the usual assumption. His uncertainty was not a gap in his
knowledge to be corrected — it was a correct signal about a defective instruction, and it was more
accurate than the judgement of three sessions that had reviewed the same text. A more confident
owner would have clicked ahead, produced a remotely-managed tunnel and a token, and the failure
would have been found at apply time on `vault-dev`.

## Remediation

### Applied

- Card `action-cloudflare-vault-tunnel-dashboard-2026-09-17` held **open**, with `checkedBy: owner`
  and a `checkResult` stating plainly that the error was in the instruction and not in anything the
  owner did, that step 1 genuinely stands, and that nothing is at risk while it waits.
- The card no longer contains the impossible steps; they are replaced with a hold notice, so it
  cannot be worked from by anyone, including a future session.
- PM notified to stop relaying the walkthrough. The stale `Zero Trust > Networks > Tunnels` path was
  flagged separately, since it may have been reused elsewhere.
- The design was **not** changed to match the dashboard. Moving to a remotely-managed tunnel would
  relocate the ingress rule — the property that the tunnel may reach exactly one service and must
  refuse everything else — out of a reviewed repository and into a dashboard, where anyone with an
  account login could widen it with no review and no record. On the host intended to hold financial
  data, that is the wrong trade, and it would put a decision-A tripwire event one click away from
  being unrecorded.

### Follow-up

- **Open, owner's decision:** build `-Action Create` in `tools/VaultTunnelKey.ps1` — a guided flow
  that performs the Cloudflare login as a browser popup, creates the locally-managed tunnel, and
  stores the credential straight into the existing DPAPI path, with no terminal step for the owner
  and no credential ever printed, written to a file, or placed in a process list. This is what makes
  the card completable. It had not been built when this was written.
- **Open:** the Access application and policy genuinely are dashboard work and remain so. Their
  navigation path should be re-sourced from Cloudflare's documentation before it is handed over,
  not written from memory.

## Lessons learned

### What worked

- **Verifying the owner's claim instead of trusting it.** The card was not resolved on the press of
  **I did it – check it**; the comment was read. A session that had auto-resolved on the claim would
  have closed the card, reported the step complete, and buried the defect.
- **Checking a peer's report rather than relaying it.** Three claims crossed sessions this evening
  and two were wrong on first telling — a phantom Tailscale section that came from a stale worktree,
  and a "no rescue procedure exists" finding that came from ripgrep honouring `.gitignore`. Both
  were caught by going to `origin/main` and to the file. The PM also independently re-verified this
  defect against `origin/main` rather than accepting it second-hand.
- **Running tests rather than asserting them.** Executing the guard suite surfaced two defects in it
  that reading it had not.

### What didn't

- **Verification effort was allocated by audience, not by consequence.** Machine-facing facts got
  primary sources; human-facing instructions got none, in the same change.
- **A read-back confirmed existence, not correctness.** Reading the card back after filing proved
  the write had landed. It said nothing about whether the content could be acted on, and it was
  easy to mistake one for the other.
- **Review asked whether the instruction was clear, never whether it was achievable.** Four sessions,
  one defect, zero detections.

### Preventive measures

Proposed as rule candidates; promotion is the PM's call under `docs/LESSONS.md`.

1. **An instruction to a person is a claim and needs the same evidence as a claim to a machine.**
   Before an action card is filed, every step must be traced to a primary source or performed. If a
   step names a screen, a menu path or a button, that path is read from current vendor documentation
   at filing time, and the card records when it was read.
2. **Check achievability, not just clarity.** For each step, ask what artifact it produces and
   whether the next step can consume it. A chain that is lucid at every step and broken between two
   of them is the failure this postmortem exists for.
3. **"I don't know how" is a defect report until proven otherwise.** Treat owner confusion as
   evidence about the instruction before treating it as a gap in the owner's knowledge. Re-derive
   the steps before re-explaining them.
4. **A card read-back proves the write landed, not that the card is right.** Say which one was
   checked.

### Related, same evening, same family

Four other near-misses shared the shape "confidently stated, not verified, caught by someone else":

- `docs/PLAN.md` instructed the owner to set OVH's firewall to deny all inbound, which would have
  killed the tunnel's return traffic — OVH's edge firewall is stateless. Caught by `github-b6`.
- A verification asserted that `cloudflared` opens no non-loopback socket. Its outbound QUIC sockets
  bind to the wildcard address, so it would have failed on a healthy host. Caught by `github-b6`
  from live observation of the edge.
- `docs/BREAK_GLASS.md` told the reader to restore the tunnel credential with an owner and mode the
  role rejects, which would have produced a recovered but unconfigurable host. Caught by
  `github-29` cross-checking the document against the role's own assertion.
- A retracted card-provenance heuristic briefly had two sessions' unattended watchers primed to
  reopen genuine owner answers. Caught by `github-0c` re-deriving it across 114 cards.

The common thread is not carelessness; every one of these was written by a session doing careful
work. It is that **confidence and verification were decoupled**, and the strength of the statement
carried no information about whether anyone had checked it.
