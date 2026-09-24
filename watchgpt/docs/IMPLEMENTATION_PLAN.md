# WatchGPT: Implementation Plan

This plan is for the agent or engineer who takes the prototype to the App Store. Read `SPEC.md` first, then `API.md`. The research in `../research/` is the evidence behind each decision; cite it when you change one.

**Ground rules**
- The protocol in `API.md` is the contract. Change it there first, then in the server tests, then in both clients.
- Anything marked *(unverified)* in research, or listed in `watchos/README.md`, is verified on a **physical cellular watch** before it's built upon. The simulator permits networking that real devices deny (TN3135).
- Keep the mock providers working. `npm test` must pass offline.

---

## M0: Device spike (≈1 week) — do this first
Goal: kill or confirm the platform risks before building UI. Use a physical **Apple Watch Series 9+ or Ultra 2+ with cellular** on watchOS 27.x, with the paired iPhone **powered off**.

| # | Experiment | Pass criteria |
|---|---|---|
| 1 | Turn mode: `URLSession.bytes(for:)` against `/v1/turns` (deployed gateway, real providers) | First `text.delta` arrives < 150 ms after the server sends it (no out-of-process buffering). p50 first audio < 2.5 s on LTE |
| 2 | Live: `await AVAudioSession.activate()`, then an NWConnection WebSocket to `/v1/live` | Socket stays up > 10 min with the 30 s re-activate. Resume recovers in < 1.5 s when the grant drops |
| 3 | Same as #2 without re-activate | Record the actual revocation time on 27.x (was ~36 s on 26.5) |
| 4 | Voice-processing I/O on the watch speaker | The assistant's audio doesn't trigger `speech.started` (no self-barge-in) |
| 5 | Battery | mAh per 10 min of Live on LTE, and per 20 turns. Informs the caps |
| 6 | Wrist down mid-Live | Audio continues. The session survives the screen turning off |
| 7 | Control on the Ultra Action button | Opens the app straight into Listening |
| 8 | Apple PCC `LanguageModelSession` on watchOS 27 | Latency and quality for a free tier (optional) |

**Deliverable:** `docs/SPIKE_RESULTS.md` with numbers. Update the risks in `SPEC.md` §9.
**If #2 fails:** try the CallKit-wrapped session (TN3135 allows it). If that fails too, Live becomes half-duplex over turn mode, and M2 changes scope.

## M1: Turn-mode MVP → TestFlight (≈2–3 weeks)
**Gateway**
- [ ] Persistence: Postgres (`devices`, `entitlements`, `usage_daily`, `usage_monthly`, `conversations` with a 30-day TTL job), replacing the in-memory `store.ts`. Keep the same function signatures.
- [ ] StoreKit 2: verify the JWS with the App Store Server Library (Node). Set up App Store Server Notifications v2 for renewals and refunds. Bind `originalTransactionId`, restore on a new device.
- [ ] Real providers on by default: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`. Keep OpenRouter behind a flag.
- [ ] Rate limiting per device and per IP. Token rotation. `TOKEN_SECRET` from a secret store.
- [ ] Observability: per-turn latency breakdown (STT / TTFT / first audio), provider errors, cost per turn.
- [ ] Deploy: Fly.io or Render, 2 regions (us-east, us-west). WebSockets and streaming must not be proxy-buffered (the `X-Accel-Buffering: no` header is already set).

**Watch app** (starts from `watchos/`)
- [ ] `xcodegen generate`. Build. Fix whatever the uncompiled prototype got wrong (see the unverified list).
- [ ] Consent (C1), then Home, Listening, Answer, and Type. Offline queue.
- [ ] Paywall (C2) wired to StoreKit. Server `402` routes to the paywall.
- [ ] Complication and Smart Stack widget with deep links.
- [ ] Settings: model (Fast / Smart), spoken replies on/off, delete my data.

**Exit criteria:** 10 external TestFlight users use it on LTE for a week. p50 first audio < 2.5 s. Crash-free > 99%.

## M2: Live mode (≈2 weeks, gated on M0 #2)
- [ ] Gateway: move the live-session registry to Redis so resume works across instances. Sticky routing by `session_id` is the simpler alternative.
- [ ] Realtime provider hardening: reconnect upstream, truncate history, 60 s idle auto-end. Gemini 3.1 Flash Live adapter as fallback.
- [ ] Watch: LiveView (B1–B4), 30 s re-activate, resume, AEC, mute, minutes-left meter, interruption handling.
- [ ] Monthly Live metering shown in Home and in the Live end summary.

## M3: Polish & launch (≈2 weeks)
- [ ] **Name + icon** (no "GPT"). App Store assets. Privacy label. Age-rating questionnaire. 5.1.2(i) wording reviewed.
- [ ] Control (Action button, Control Center), double-tap shortcut, App Shortcuts phrases.
- [ ] Opus uplink for Live via swift-opus: about 16× less bandwidth than PCM. Gateway transcodes to PCM for the provider.
- [ ] Haptics pass. Always-On states. Accessibility (VoiceOver labels, Dynamic Type on answers).
- [ ] Small Business Program enrollment. Launch.

## Later
- "Connect OpenRouter" BYO tier (OAuth PKCE; `research/04`).
- Apple PCC free tier (watchOS 27).
- Optional iPhone companion for history and settings.
- "Live+" tier.
- Watch **ChatPass** (OpenAI subscription sharing) and any Anthropic equivalent. If one launches, it's a major simplification.

---

## Repo map
```
watchgpt/
├── README.md                 ← start here (recommendations)
├── docs/
│   ├── SPEC.md               ← product + technical spec
│   ├── API.md                ← wire protocol (the contract)
│   └── IMPLEMENTATION_PLAN.md
├── research/                 ← 01 competitors · 02 watchOS · 03 voice/inference · 04 BYO subscription · 05 business/App Store
├── mockups/index.html        ← 16 annotated screens
├── server/                   ← gateway prototype (Node 22, TS, no build step)
│   ├── src/                  ← server, turn pipeline, live relay, providers
│   ├── public/index.html     ← browser watch simulator (reference client)
│   └── test/                 ← end-to-end tests (mock providers)
└── watchos/                  ← SwiftUI watch app source (XcodeGen), uncompiled
```
