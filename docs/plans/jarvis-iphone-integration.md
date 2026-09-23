# Jarvis on iPhone: Replacing Siri

_Sep 23, 2026 · drafted with Claude Code_

> **Superseded (2026-09-23):** this was drafted before discovering `yodatech1988/jarvis`, an existing, already-working assistant project with a stricter approval-gated write architecture, multi-user support already shipped, and an iPhone surface already scaffolded (HTTP + iOS Shortcuts, `docs/PLAN.md` Session 12). This document is kept for its comparison of invocation approaches, but the actual next steps live in that repo, not here — see the note at the end of this document.

## Goal and constraints

"Jarvis instead of Siri" means: a voice/text assistant with real tool access (calendar, messages, home control, custom backend logic) that you reach for by default, with an invocation path that's as fast and low-friction as Siri's.

Apple's hard limits as of iOS 18/26:

- No third-party app can register as the system default assistant. "Hey Siri" and the long-press side button always launch Apple's Siri.
- No background always-listening wake-word for third-party apps (no mic access while the app isn't in foreground/active use, aside from narrow Live Activity/VoIP exceptions).
- Siri itself can hand off specific intents to your app via App Intents/App Shortcuts, but Siri stays the entry point — it's delegation, not replacement.

So the plan targets the closest achievable thing: Jarvis becomes the assistant you actually use day-to-day via the fastest non-Siri invocation paths iOS allows (Action Button, Control Center, home-screen icon, widget), while Siri remains present at the OS level for what Apple reserves for itself.

## Architecture options

| Option | Invocation | Effort | Feel | Key limitation |
| --- | --- | --- | --- | --- |
| A. Shortcuts + custom Siri phrase | Say a custom phrase, briefly touches Siri, then hands off | Days | Clunky, one-shot Q&A | No true wake word, Shortcuts speech capture is unreliable, no ambient conversation |
| B. Standalone app, push-to-talk | Action Button, Control Center widget, or app icon tap | Weeks | Closest to "Jarvis": instant mic, streaming replies, full tool access | Never truly hands-free; app must be foregrounded or bound to a hardware trigger |
| C. App Intents / Apple Intelligence handoff | Siri itself routes matching phrases to your app | Weeks, iOS 18+ only | Most native-feeling, works alongside real Siri | Only covers narrow, pre-declared intents — not open-ended conversation |

**A — Shortcuts bridge:** a custom Siri phrase triggers a Shortcut that POSTs the transcribed text to your Jarvis backend and speaks the JSON response back. Zero App Store review, buildable in an afternoon, but every invocation still visibly bounces through Siri's UI first and Shortcuts' speech-to-text quality is inconsistent.

**B — Standalone app:** a purpose-built iOS app owns the whole loop — mic capture, speech-to-text, sending to your Jarvis backend, streaming the reply, text-to-speech. Bound to the Action Button (iPhone 15 Pro+) or a Control Center button/widget for one-tap access from anywhere, including the lock screen. This is the only option that feels like an assistant rather than a form you fill out.

**C — App Intents/Apple Intelligence:** you declare specific capabilities ("ask Jarvis about X", "log a task in Jarvis") as App Intents; Siri can then route matching phrases to your app instead of handling them itself. Tightest OS integration available to third parties, but it's intent-matching, not general conversation — you're still building B underneath it to do the actual work.

## Recommendation

Build B (standalone app) first, then layer C (App Intents) on top once the core assistant works. Skip A except as a throwaway prototype to validate the backend, if that's useful.

Reasoning: A caps out at a novelty demo — it can never feel like "my assistant," only like a voice-triggered API call. C alone is a dead end — without an app behind it, there's no assistant to hand off to. B is the only option that delivers the actual experience (fast invocation, streaming conversation, tool use, memory across turns), and it's a strict prerequisite for C anyway, since App Intents just point Siri at functionality your app already has.

## System components

| Layer | Role | Candidate approach |
| --- | --- | --- |
| Invocation | Trigger a Jarvis session fast | Action Button (iPhone 15 Pro+), Control Center widget, home-screen icon, Lock Screen widget |
| Speech-to-text | Voice → text | Apple's on-device Speech framework (free, private, fast) or streamed Whisper API if higher accuracy is needed |
| Reasoning / tools | Understand intent, call tools, hold context | Backend service calling Claude (or another LLM) with tool definitions — calendar, reminders, home control, custom logic |
| Text-to-speech | Reply → voice | Apple's AVSpeechSynthesizer (free, on-device) or a higher-quality streamed TTS API for a more natural voice |
| Backend | Hosts the LLM/tool layer, auth, conversation state | Small API server (could reuse infra from this project or a fresh lightweight service) |
| iOS client | Mic capture, UI, streaming display, TTS playback, calls backend | Native Swift/SwiftUI app (best latency and Action Button/widget support) |

The iOS client should be native Swift, not cross-platform (React Native/Flutter), because Action Button binding, Control Center widgets, and low-latency audio capture are most reliable through first-party APIs.

## Multi-user support

Each person needs to be a known identity to the backend, not just a device hitting an API — tool calls like "add to my calendar" or "read my messages" have to resolve to the right person's data, and conversation history/preferences shouldn't bleed between you and your wife.

**Design:**

- Each phone gets its own lightweight login (a per-user API token issued at setup — no need for a full OAuth system for a two-person household). The iOS app stores its token in the Keychain and sends it with every backend request.
- The backend maps each token to a user record: name, linked accounts (her calendar vs. yours, her reminders vs. yours), and separate conversation history.
- Tool definitions take the authenticated user as context automatically, so "my calendar" always resolves correctly without the user having to specify whose.
- Shared tools (e.g. a household grocery list, home automation) are scoped to the household rather than a single user, so either phone can read/write them.

**When to build it:** bake user identity into the backend from Phase 0 (the proof-of-concept), even with just one hardcoded user — retrofitting auth after tools already assume a single user is more rework than starting with it. Actually onboarding her phone (issuing her a token, linking her accounts) fits naturally into Phase 2, once the standalone app exists for her to install.

**Onboarding flow (Phase 2):** she installs the app → enters a setup code you generate from your own app/backend (or scans a QR code) → app exchanges it for her personal token → she links her calendar/accounts on first launch.

## Phased build plan

### Phase 0 — backend proof of concept (few days)

- Stand up a minimal API: text in, LLM response out, no voice yet.
- Wire up 2-3 real tools (e.g. calendar read, a reminder/note write) to prove the tool-calling loop works end to end.

### Phase 1 — Shortcuts bridge (few days, optional)

- Custom Siri phrase → Shortcut → POST to the Phase 0 backend → speak the reply.
- Purely a smoke test for the backend and tools; not meant to be the daily driver.

### Phase 2 — standalone app MVP (2-4 weeks)

- SwiftUI app: push-to-talk button, on-device STT, streaming text reply, on-device TTS.
- Bind to the Action Button and add a Control Center/home-screen widget for fast access.
- Persist conversation history/context across turns.
- Daily-driver test: use it instead of Siri for a week, track where it fails.

### Phase 3 — tool and capability expansion (ongoing)

- Add tools progressively: messages, home automation (HomeKit), web search, app-specific actions.
- Add memory/personalization (preferences, recurring routines).

### Phase 4 — App Intents / Apple Intelligence integration (iOS 18+, after Phase 2 is solid)

- Declare App Intents for your most common request types so Siri can hand off to Jarvis directly for those.
- Add a Live Activity or widget for ambient status/quick replies without fully opening the app.

## Risks and platform constraints

- **No true hands-free wake word.** iOS reserves always-listening background mic access for Apple's own Siri; every invocation needs a physical or on-screen trigger (Action Button, widget tap).
- **App must be reachable quickly or the illusion breaks.** If invocation takes more than 1-2 taps, it stops feeling like an assistant and starts feeling like a chat app.
- **API costs and latency.** Streaming LLM responses plus STT/TTS round-trips need to stay fast (sub-2s to first audio) to feel conversational; costs scale with usage if using hosted APIs.
- **Background/lock-screen limitations.** Actions while the phone is locked or the app is backgrounded are constrained by iOS; some tool actions (e.g. sending messages) may require the app to be active.
- **Apple policy drift.** iOS periodically expands third-party Siri/App Intent capabilities (e.g. Apple Intelligence app integration) — worth re-checking platform capabilities each major iOS release rather than assuming today's limits are permanent.
- **Privacy/security.** Voice data and tool access (calendar, messages, home control) need proper auth and encryption if the backend isn't fully on-device.

## Next steps

- [ ] Decide if this lives in a new repo/project or as a module of an existing one
- [ ] Pick the LLM/backend provider and confirm hosting (self-hosted vs. serverless)
- [ ] Confirm target device: does it have an Action Button (iPhone 15 Pro or later), or should invocation lean on widgets/Control Center instead?
- [ ] Decide Phase 1 (Shortcuts bridge) in or out — useful as a quick backend smoke test, but skippable if you'd rather go straight to the app
- [ ] Scope the first tool set for the Phase 2 MVP (calendar? reminders? something else?)

## Where the real work is

The actual project is `yodatech1988/jarvis` (private repo). It already has: a working assistant on Discord + terminal with tasks/reminders/notes/durable memory; a write-approval architecture (the model can only propose external writes — a human approves every one); and multi-user support shipped 2026-09-23.

The iPhone surface is Session 12 in that repo's `docs/PLAN.md`: `src/surfaces/http.js` (message/pending/approve/reminders endpoints, token auth) is built, and an iOS Shortcut (`tools/ios-shortcut/Ask Jarvis.shortcut`) already exists. What's left, per that plan:

1. Pick the transport (home-wifi-only is the zero-cost default; Tailscale or a Cloudflare Tunnel are upgrades if that's too limiting)
2. Generate a real `JARVIS_HTTP_TOKEN`
3. Live-test a full round trip from a real iPhone on the chosen transport, including one approval

Continue there, not here.
