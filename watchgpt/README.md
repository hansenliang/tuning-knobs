# WatchGPT (codename)

A standalone Apple Watch app for talking to a frontier AI model. You dictate or talk live, over LTE or Wi-Fi, with no iPhone required.

This folder has four things: the research, the design, a working prototype, and a build plan. Another agent can pick it up from here.

| | |
|---|---|
| **Spec** | [`docs/SPEC.md`](docs/SPEC.md): product, architecture, economics, risks |
| **Protocol** | [`docs/API.md`](docs/API.md): the watch ↔ gateway contract |
| **Plan** | [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md): M0 device spike through launch |
| **Mockups** | [`mockups/index.html`](mockups/index.html): 16 annotated watch screens |
| **Gateway prototype** | [`server/`](server/): runs offline, `npm start`, 11 e2e tests |
| **Browser watch simulator** | served by the gateway at `/`: the working reference client |
| **watchOS app source** | [`watchos/`](watchos/): SwiftUI + XcodeGen, uncompiled; device checklist inside |
| **Research** | [`research/`](research/) 01 competitors · 02 watchOS platform · 03 voice/inference · 04 bring-your-own-subscription · 05 business & App Store |

## Recommendations (as of 2026-09-24)

1. **Build it.** No frontier lab has an Apple Watch app. Siri AI in watchOS 27 depends on the iPhone and is slow standalone. The incumbents are small indie apps.
2. **Run our own gateway.** The watch speaks one small protocol, and providers sit behind it. That keeps keys, quotas and billing on the server, and lets us swap models without shipping an app update.
3. **Ship push-to-talk first, over plain HTTPS.** watchOS allows it everywhere. Live voice needs WebSockets, which watchOS allows only during an active audio session, and a live bug revokes that about every 36 s. The prototype mitigates this with 30 s re-activation plus server-side session resume. Prove it on a real cellular watch before committing (M0).
4. **Models:**
   - Claude Haiku 4.5 (fast) and Sonnet 5 (smart), called **directly** on the Anthropic API.
   - OpenAI `gpt-realtime-2.1-mini` for Live.
   - OpenAI mini transcription and TTS.
   - OpenRouter is optional. It has no realtime endpoint, charges a 5.5% fee, and its ToS forbids "reselling API access… or developing a competing service".
5. **One price:** $9.99/month, a 7-day trial, unlimited asks, and 60 Live minutes a month. Live must be metered: a heavy uncapped user costs $12–18/month.
6. **No login.** The StoreKit subscription is the account.
7. **Consent screen first.** It must name the AI providers (Guideline 5.1.2(i), 2025).
8. **Bring-your-own ChatGPT or Claude subscription isn't possible legitimately.** Anthropic explicitly bans it and enforces the ban; OpenAI only has a login beta that doesn't cover billing. The legit alternatives:
   - "Connect OpenRouter" (OAuth PKCE)
   - Apple's free on-device/PCC model on watchOS 27, as a free tier
9. **Rename before launch.** "GPT" in an app name gets rejected, which is how *watchGPT* became *Petey*.

## Try the prototype
```bash
cd server && npm install && npm start
open http://localhost:8787     # watch simulator: mic, text, Live, "Simulate network drop"
npm test                       # offline e2e tests incl. live resume
```
Add `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` for real answers and voices (see `server/README.md`).
