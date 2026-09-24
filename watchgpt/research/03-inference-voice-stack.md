# 03 — Inference & Voice Stack (WatchGPT)

*Researched 2026-09-24. All prices are list/PAYG USD as seen on 2026-09-24.*

> **Method caveat:** The sandbox's egress proxy blocked direct fetches of vendor pages (openai.com, ai.google.dev, openrouter.ai, etc.). Every number below comes from 2026-dated web-search results. Those results cite the vendor pages or recent (Jul–Sep 2026) third-party trackers. Numbers taken only from third-party trackers are marked **(3P)**. Claims I couldn't cross-check are marked **(unverified)**. Re-check the ★ items on the vendor pricing pages before committing.

---

## TL;DR

| Decision | Recommendation |
|---|---|
| Dictation (push-to-talk) | **Cascaded over plain HTTPS**: watch uploads Opus/AAC clip → our server → streaming STT (Deepgram Nova-3 / gpt-4o-mini-transcribe) → **frontier text LLM via OpenRouter** (SSE) → TTS (Cartesia Sonic / Inworld / gpt-4o-mini-tts) streamed back. |
| Live full-duplex | **OpenAI `gpt-realtime-2.1-mini` direct (not via OpenRouter)**, relayed by our server over one WebSocket to the watch. Upsell tier: `gpt-realtime-2.1` or GPT-Live-1. |
| Live fallback | **Gemini 3.1 Flash Live** (cheapest audio rates, 16 kHz in). Or a Pipecat cascade (Deepgram Flux → Haiku/Sonnet via OpenRouter → Cartesia) when we need a *Claude* voice or the S2S providers are down. |
| OpenRouter's role | The **text-LLM leg only**: dictation replies, cascade fallback, model choice, and billing consolidation. It has **no realtime/WebSocket endpoint**, so it can't carry live mode. |
| Orchestration | **Pipecat** (Python) with a `FastAPIWebsocketTransport` and a custom serializer. LiveKit is a poor fit because it's WebRTC-centric and has no watchOS SDK. Vapi/Retell add $0.05–0.07/min. |
| Watch↔server codec | **Opus, mono, 16 kHz, ~16–24 kbps VBR, 20 ms frames, in-band FEC** in both directions. The server transcodes to/from PCM16 for the providers. PCM16 at 24 kHz is 384 kbps, about 16× more data. |
| Est. COGS | Light dictation user **≈ $1.5–5/mo**. Heavy live user (20 min/day) **≈ $15/mo** (realtime-mini), **$17–22** (cascade), **$12–36** (Gemini Live, depends on context growth), **$42+** (realtime flagship). |

**Platform blocker (hand-off to the watch researcher):** watchOS treats WebSockets as *low-level networking*. It allows them only while the app holds an **active audio session** (or on the CallKit VoIP path). Reports say `URLSessionWebSocketTask` is denied even then, and the socket must be opened in-process (Network framework) after an async `AVAudioSession.activate(options:)`. There is **no WebRTC on watchOS**. Dictation over plain HTTPS URLSession is unaffected. Sources: [TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos), [Apple forum 779017](https://developer.apple.com/forums/thread/779017), and a production watch app hitting exactly this: [ReviewStage/luke PR #704](https://github.com/ReviewStage/luke/pull/704) and [#1459](https://github.com/ReviewStage/luke/pull/1459) ("no WebRTC for watchOS … the service holds the primary socket and relays audio"). That confirms the **own-backend relay** architecture.

---

## 1. Speech-to-speech (S2S) realtime APIs

Token math. OpenAI: user audio = 1 token/100 ms (600 tok/min), assistant audio = 1 token/50 ms (1,200 tok/min). Gemini: ~25 tok/s of audio. **Every S2S API re-bills the accumulated conversation context as input on each turn.** OpenAI discounts that heavily through caching. Gemini bills the full context window per turn. So cost grows with session length.

| API (model) | $ list price | Est. $/conv-min* | Transport | Audio in/out formats | Latency | Via OpenRouter? |
|---|---|---|---|---|---|---|
| **OpenAI gpt-realtime-2.1** (Jul 6 2026) ★ | audio $32 in / $64 out per 1M; cached in $0.40 | **~$0.07 typical, $0.15 worst (measured, 3P)** | WebSocket, WebRTC, SIP | `audio/pcm` 24 kHz PCM16, `audio/pcmu`/`pcma` (G.711). Opus only inside WebRTC | p95 cut ≥25% vs prior (vendor claim) | **No** |
| **OpenAI gpt-realtime-2.1-mini** ★ | audio $10 in / $20 out per 1M; cached $0.30 | **~$0.02–0.03** (my model, below); 3P says $0.02–0.05 with caching | same | same | faster than flagship | **No** |
| **OpenAI GPT-Live-1** (API since Sep 10 2026) | **$0.05/session-min**, billed per second, + backend model tokens | ~$0.05 + backend | `v1/live/sessions`: WebRTC, WebSocket, SIP. WS reportedly needs the project key, i.e. server-side only (unverified) | PCM (assumed same as Realtime, unverified) | full-duplex, listens while speaking | **No** |
| **Google Gemini 3.1 Flash Live** (preview, Mar 2026) ★ | text $0.75/$4.50 per 1M; audio ≈ $3 in / $12 out per 1M ≈ **$0.005/min in, $0.018/min out** (3P) | **~$0.015 short sessions → $0.05+ long sessions** (full context re-billed per turn) | WebSocket (ephemeral tokens for client-direct) | in: raw PCM16 **16 kHz** (resamples any rate); out: PCM16 24 kHz | "improved vs 2.5 native audio" | **No** (Flash text/TTS yes) |
| **xAI Grok Voice Think Fast 2.0** | **$0.08/audio-min** + $0.004 text (3P); v1.0 at $0.05 is deprecated | $0.08 | WebSocket, OpenAI-Realtime-*compatible* (not identical); JSON or **binary frames** | PCM 24 kHz, G.711, **Opus 24 kHz** (most watch-friendly) | "fastest" (vendor) | No |
| **Amazon Nova 2 Sonic** (Bedrock) | $3 in / $12 out per 1M speech tokens; text $0.33/$2.75 | ~$0.01–0.02 (unverified) | Bedrock `InvokeModelWithBidirectionalStream` (**HTTP/2**, AWS SigV4). ~8-min session, needs rotation | LPCM 16 kHz in / 24 kHz out | ok (unverified) | No |
| **Anthropic** | **No audio/realtime/speech API.** Messages API is text+image+PDF only. Voice exists only in consumer apps and Claude Code dictation | n/a | — | — | — | Claude is on OpenRouter as a *text* model |
| **ElevenLabs Agents** | $0.08/min (was $0.10) + LLM passthrough | ~$0.09–0.12 | WebSocket/WebRTC | PCM/µ-law (unverified) | good | No |
| **Hume EVI (3/4)** | $0.07 → $0.04/min by tier | $0.04–0.07 + LLM | WebSocket | many containers + linear16 PCM | ~1.2 s practical (3P) | No |
| **Ultravox Realtime** | **$0.05/min** all-in (first 30 min free) | $0.05 | WebSocket/WebRTC/SIP | PCM (unverified) | good | No |

\* A conversation-minute here means a mix of user, assistant and silence, with 5-min sessions and ~4 turns/min.

Sources: [OpenAI gpt-realtime-2.1 announcement (MarkTechPost, 2026-07-06)](https://www.marktechpost.com/2026/07/06/openai-gpt-realtime-2-1-mini-reasoning-realtime-api/) · [OpenAI community announcement](https://community.openai.com/t/new-realtime-models-on-the-api-gpt-realtime-2-1-and-gpt-realtime-2-1-mini/1385896) · [layer3labs Realtime pricing](https://www.layer3labs.io/guides/openai-realtime-api-pricing) (3P) · [HackerNoon: 4,000 measured sessions](https://hackernoon.com/openai-realtime-api-pricing-in-2026-real-world-data-from-4000-measured-sessions) (3P) · [OpenAI GPT-Live guide](https://developers.openai.com/api/docs/guides/live) · [GPT-Live-1 pricing (eesel)](https://www.eesel.ai/blog/gpt-live-1-pricing) · [Gemini 3.1 Flash Live model page](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-live-preview) · [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing) · [Gemini Live price (TokenCost, 3P)](https://tokencost.app/models/gemini-3-1-flash-live) · [Gemini Live session mgmt](https://ai.google.dev/gemini-api/docs/live-session) · [Gemini forum on per-turn context billing](https://discuss.ai.google.dev/t/pricing-of-speech-to-speech-live-model/140340) · [xAI models/pricing](https://docs.x.ai/developers/models) · [Grok Think Fast 2.0 tutorial (DataCamp)](https://www.datacamp.com/tutorial/grok-voice-think-fast-2-0) · [Nova pricing](https://aws.amazon.com/nova/pricing/) · [Nova bidirectional API](https://docs.aws.amazon.com/nova/latest/userguide/speech-bidirection.html) · [Anthropic SDK audio-input feature request](https://github.com/anthropics/anthropic-sdk-python/issues/1198) · [ElevenLabs Agents pricing](https://elevenlabs.io/pricing/agents) · [Hume audio docs](https://dev.hume.ai/docs/speech-to-speech-evi/guides/audio) · [Ultravox pricing](https://www.ultravox.ai/pricing)

**Operational limits that matter:**
- **OpenAI Realtime:** sessions max out at **60 min**. Ephemeral client secrets exist, but we relay server-side anyway.
- **Gemini Live:** audio-only sessions run **15 min** unless context-window compression is on. Each connection lasts ~10 min, so plan for reconnects. Session-resumption tokens are valid for 2 h.
- **Nova Sonic:** sessions last ~8 min and must be rotated.
- **Grok:** 30-min session cap and 100 concurrent sessions per team (3P).

---

## 2. OpenRouter (as of Sep 2026)

| Capability | Status |
|---|---|
| Text chat completions, streaming SSE, tools | ✅ Core product, OpenAI-compatible, 400+ models including Claude, Gemini, GPT and Groq/Cerebras-hosted open models |
| Audio **input** in chat (`input_audio`, base64) | ✅ wav, mp3, aac, ogg, flac, m4a, aiff, pcm16/pcm24. Support varies by model |
| Audio **output** in chat | ✅ Only on audio-capable models (e.g. `openai/gpt-audio`, `gpt-audio-mini`). **Requires `stream: true`**; audio arrives in `delta.audio` SSE chunks |
| `/api/v1/audio/transcriptions` (STT) | ✅ New: whisper-1, gpt-4o(-mini)-transcribe, "GPT Transcribe" ($0.000075/s ≈ $0.0045/min), Fish Audio Transcribe 1 ($0.0001/s). File upload, not streaming |
| `/api/v1/audio/speech` (TTS) | ✅ New: gpt-4o-mini-tts, Gemini Flash TTS, Voxtral Mini TTS |
| **Realtime / WebSocket / WebRTC session API** | ❌ **None documented.** SSE output is not full-duplex. No `gpt-realtime`, Gemini Live or Grok Voice |
| Fees | **5.5% on credit purchases** (min $0.80). Crypto 5%. New Business tier 8% (Sep 2026). Model token prices pass through at provider list |
| BYOK | Free up to **$25k/mo** of list-price inference, then 5% (changed Aug 2026 from 1M free requests). Enterprise: $200k/mo free |
| Latency overhead | ~25–40 ms added at the edge (vendor). One 3P benchmark even saw faster TTFT than OpenAI direct |

**Fit verdict:**
- **Text leg: good.** Provider fallback, instant model swaps (Haiku ↔ Sonnet ↔ Gemini Flash ↔ GPT mini), one invoice. 5.5% is cheap insurance. Use BYOK for the biggest provider if spend grows, since BYOK is free under $25k/mo.
- **Dictation audio: optional.** OpenRouter STT/TTS endpoints are fine for non-streaming clips. Dedicated streaming vendors give lower TTFB.
- **Live voice: unusable.** Go direct to OpenAI, Google or xAI.

Sources: [OpenRouter audio docs](https://openrouter.ai/docs/guides/overview/multimodal/audio) · [Audio APIs announcement](https://openrouter.ai/blog/announcements/announcing-audio-apis/) · [STT collection](https://openrouter.ai/collections/speech-to-text-models) · [gpt-audio-mini page](https://openrouter.ai/openai/gpt-audio-mini) · [Latency docs](https://openrouter.ai/docs/guides/best-practices/latency-and-performance) · [Router latency benchmark (Opper, 3P)](https://opper.ai/blog/llm-router-latency-benchmark-2026) · [Fees/BYOK (TrueFoundry, 3P)](https://www.truefoundry.com/blog/openrouter-pricing) · [BYOK change (aireiter, 3P)](https://aireiter.com/blog/openrouter-byok-fees-fallback-guide)

---

## 3. Cascaded pipeline components

### 3a. Streaming STT

| Vendor / model | Price | Latency / notes | Streaming protocol | Input formats |
|---|---|---|---|---|
| **Deepgram Flux** (conversational, built-in end-of-turn) ★ | $0.0065/min EN, $0.0078 multi (PAYG) | Model-integrated turn detection, the key feature for voice agents | WebSocket | linear16, **Opus/Ogg**, many containers |
| **Deepgram Nova-3** | $0.0048/min streaming (mono), $0.0058 multi | Sub-300 ms partials (3P) | WebSocket | same |
| AssemblyAI Universal-Streaming | $0.15/hr = **$0.0025/min** | Voice-agent-tuned endpointing | WebSocket | PCM16 (unverified: Opus) |
| Soniox real-time | $0.12/hr = **$0.002/min** | Strong multilingual | WebSocket | PCM, Opus etc. (unverified) |
| OpenAI gpt-4o-mini-transcribe / gpt-4o-transcribe | $0.003 / $0.006 per min | Also usable as Realtime transcription sessions | HTTP (file), Realtime WS | wav/mp3/m4a/webm…; realtime PCM16 |
| Groq Whisper-large-v3-turbo | **$0.04/hr** (~$0.0007/min) | ~200× real-time **batch** — great for PTT clips, not true streaming | HTTP | flac/mp3/m4a/ogg/wav/webm |
| Cartesia Ink-2 | 3 credits/s (Ink-1: 1 credit/s) ≈ $0.005/min on Scale (unverified) | ~100 ms transcript latency (vendor) | WebSocket | PCM |

### 3b. Streaming TTS

~15 chars ≈ 1 s of speech, so 1 spoken minute ≈ 900 chars.

| Vendor / model | Price | $/spoken min | TTFB | Streaming output formats (watch relevance) |
|---|---|---|---|---|
| **Cartesia Sonic-3.x** (3.6, Aug 2026, tops Artificial Analysis arenas) | 1 credit/char. Startup $39/1.25M, Scale $239/8M → **~$30/M chars** | ~$0.027 | **~90 ms** (Turbo ~40 ms) | WS/SSE: **raw only** (pcm_s16le/f32le, µ-law, A-law), any rate incl. 16 kHz. Bytes endpoint: wav/mp3 |
| **Inworld TTS-2 Flash / TTS-2** | $15 / $25 per M chars (PAYG); lower on Growth | $0.014 / $0.023 | <100 ms | PCM, MP3, Opus (unverified) |
| ElevenLabs Flash v2.5 | ~$0.05/1k chars = $50/M | $0.045 | ~75 ms model-only | MP3 (default), PCM, µ-law; Opus (unverified) |
| OpenAI gpt-4o-mini-tts | $0.60/M text in + $12/M audio out ≈ **$0.015/min** | $0.015 | ~200–400 ms (unverified) | **mp3, opus, aac, flac, wav, pcm**. Chunked streaming, so it can emit **Opus directly** |
| Deepgram Aura-2 | $0.030/1k chars = $30/M | $0.027 | low (sub-200 ms, unverified) | WS: linear16/µ-law/A-law only. REST: mp3, **opus**, aac, flac |
| Rime (Arcana/Mist) | not verified this session | — | — | (unverified) |
| Gemini Flash TTS, Voxtral Mini TTS | via OpenRouter `/audio/speech` | (unverified) | — | — |

**Watch implication:** the lowest-TTFB vendors (Cartesia WS, Deepgram WS) emit only raw PCM. So **our server should encode Opus** (libopus, trivially cheap) instead of relying on vendor Opus.

### 3c. Fast LLMs for the voice leg

| Model | $ in / out per 1M | TTFT notes | On OpenRouter |
|---|---|---|---|
| **Claude Haiku 4.5** (`claude-haiku-4-5`) | $1 / $5 | Fast, a common choice for chained voice stacks | ✅ |
| **Claude Sonnet 5** (`claude-sonnet-5`) | $2 / $10 | The "frontier feel" pick for dictation | ✅ |
| Claude Opus 5 / Opus 5.5 | $5/$25 · $4/$20 | Too slow/expensive for live; OK for "think harder" dictation | ✅ |
| GPT-5.4 mini / GPT-5 nano | $0.75/$4.50 · $0.05/$0.40 | Reasoning models add ~800 ms+ unless reasoning is set minimal | ✅ |
| Gemini 3.5 Flash / Flash-Lite | $1.50/$9 · $0.30/$2.50 (3P) | Flash family is usually the fastest TTFT among frontier labs | ✅ |
| gpt-oss-120b on Groq / Cerebras | cheap | **Groq median TTFT 234 ms; Cerebras 669 tok/s** (OpenRouter data, 2026-09-11) | ✅ |

Voice budget: LLM TTFT should be **≤ ~700 ms**, and pauses over ~800 ms feel unnatural ([WebRTC.ventures latency budget, Sep 2026](https://webrtc.ventures/2026/09/voice-ai-latency-budget/)). Always disable or minimize reasoning on the live path.

Sources: [Deepgram pricing](https://deepgram.com/pricing) · [Deepgram pricing 2026 (diyai, 3P)](https://diyai.io/ai-tools/speech-to-text/deepgram-pricing-2026/) · [Deepgram TTS WS encodings](https://developers.deepgram.com/docs/tts-websocket-streaming) · [AssemblyAI pricing](https://www.assemblyai.com/pricing) · [Soniox pricing](https://soniox.com/pricing) · [OpenAI transcription pricing (costgoat, 3P)](https://costgoat.com/pricing/openai-transcription) · [gpt-4o-mini-tts (TokenMix, 3P)](https://tokenmix.ai/blog/gpt-4o-mini-tts-cheapest-tts-api-2026) · [OpenAI TTS guide](https://platform.openai.com/docs/guides/text-to-speech) · [Groq Whisper turbo](https://console.groq.com/docs/model/whisper-large-v3-turbo) · [Cartesia pricing docs](https://docs.cartesia.ai/pricing) · [Cartesia output formats](https://docs.cartesia.ai/build-with-cartesia/capability-guides/tts-output-audio-format) · [Sonic-3.6 (MarkTechPost, 2026-08-18)](https://www.marktechpost.com/2026/08/18/cartesia-ships-sonic-3-6-a-streaming-tts-model-that-now-leads-both-artificial-analysis-speech-arenas/) · [Inworld TTS pricing](https://inworld.ai/resources/tts-api-pricing-comparison) · [ElevenLabs pricing](https://elevenlabs.io/pricing) · [ElevenLabs models](https://elevenlabs.io/docs/overview/models) · [Claude models overview](https://platform.claude.com/docs/en/about-claude/models/overview) · [OpenAI pricing (Morph, 3P)](https://www.morphllm.com/openai-api-pricing) · [Gemini pricing (puter, 3P)](https://developer.puter.com/tutorials/gemini-api-pricing/) · [Groq pricing (CloudZero, 3P)](https://www.cloudzero.com/blog/groq-pricing/)

---

## 4. Orchestration frameworks

| Framework | Model | Transports for a WebSocket-only client | S2S support | Cost | Fit for us |
|---|---|---|---|---|---|
| **Pipecat** (OSS, Python) | Self-host in our backend | `FastAPIWebsocketTransport` + pluggable `FrameSerializer` (protobuf or custom binary), so we define our own Opus framing. Also WebRTC/Daily | OpenAI Realtime, Gemini Live, **Grok Realtime**, **Nova Sonic**, plus cascaded STT/LLM/TTS services and OpenRouter as an LLM | Free (infra only) | **Best: fastest path, one framework for both modes, swap providers by config** |
| LiveKit Agents (OSS + cloud) | Agent joins a LiveKit room | **WebRTC-first.** Swift SDK has **no watchOS support**; WS-client support is an open issue | Yes | OSS free; cloud per-min | Poor: we'd need a WS↔room bridge |
| Vapi | Hosted orchestrator | Web/phone SDKs; WebSocket transport exists (unverified for custom clients) | Yes | **$0.05/min platform fee** + providers (~$0.07–0.25 all-in) | Prototype only. Kills margin at 600 min/user |
| Retell | Hosted, phone-centric | Web/phone | Partial | **$0.07/min** voice engine + LLM ($0.025/min Haiku 4.5) | No |
| Deepgram Voice Agent API | Hosted STT+TTS+orchestration on one WS | Single WebSocket (good fit) | n/a (cascade) | ~$0.06–0.07/min BYO LLM | Viable managed-cascade fallback |

Sources: [Pipecat WS transport](https://reference-server.pipecat.ai/en/stable/api/pipecat.transports.websocket.fastapi.html) · [Pipecat Grok S2S](https://docs.pipecat.ai/api-reference/server/services/s2s/grok) · [Pipecat Nova Sonic](https://docs.pipecat.ai/server/services/s2s/aws) · [LiveKit watchOS issue](https://github.com/livekit/client-sdk-swift/issues/288) · [LiveKit WS client issue](https://github.com/livekit/agents/issues/3127) · [Vapi pricing (layer3labs, 3P)](https://www.layer3labs.io/guides/vapi-pricing) · [Retell pricing (layer3labs, 3P)](https://www.layer3labs.io/guides/retell-ai-pricing) · [Deepgram Voice Agent API](https://deepgram.com/product/voice-agent-api)

---

## 5. Unit economics (COGS per user per month)

### Assumptions
- **Light user:** 10 PTT turns/day × 30 = **300 turns/mo**. Each turn: 8 s of user audio, LLM input ≈ 2,300 tok (800 system + ~1,500 history + query, before caching), output 150 tok, spoken reply ≈ 400 chars (~25 s).
- **Heavy user:** **20 live min/day = 600 min/mo**. Sessions of ~5 min, ~4 turns/min, ~50% of wall time is assistant speech. Cascade LLM turn = ~2,500 in / 60 out tokens, text context.
- OpenRouter 5.5% fee is applied to the LLM leg only. Our server, relay and bandwidth add ≈ $0.2–0.5/user/mo (Opus is ~110 MB per direction at 600 min).

**My S2S context model for `gpt-realtime-2.1-mini`, per conv-minute:**

| Component | Math | Cost |
|---|---|---|
| New user audio | 300 tok × $10/M | $0.003 |
| Assistant audio | 600 tok × $20/M | $0.012 |
| Cached context re-reads | ~65k tok per 5-min session × $0.30/M | ≈ $0.004 |
| Text/tools buffer | — | small |
| **Total** | | **≈ $0.02–0.03/min** |

The flagship is ×3.2, so ≈ $0.07/min, which matches the 3P measured "typical $0.070, worst $0.146".

**Gemini Live, same model:** base ≈ $0.0115/min. Re-billing the full audio context at ~$3/M adds ≈ $0.02–0.05/min over 5-min sessions, so the total is **≈ $0.03–0.06/min**. It drops toward $0.015 with aggressive context compression or short sessions. Whether any implicit-cache discount applies is **unverified**.

### (i) Light dictation user: 300 turns/mo

| Stack | STT | LLM | TTS | $/turn | **$/mo** |
|---|---|---|---|---|---|
| A. Deepgram Nova-3 → **Haiku 4.5** (OR) → Cartesia | $0.0006 | $0.0032 | $0.012 | $0.016 | **≈ $4.8** |
| B. gpt-4o-mini-transcribe → **Sonnet 5** (OR) → gpt-4o-mini-tts (Opus out) | $0.0004 | $0.0065 | $0.006 | $0.013 | **≈ $3.9** |
| B′. Same as B, text-only reply (no TTS) | | | | $0.007 | **≈ $2.1** |
| C. Groq Whisper-turbo → Haiku 4.5 → Inworld TTS-2 Flash | $0.0001 | $0.0032 | $0.006 | $0.009 | **≈ $2.8** |
| D. gpt-realtime-2.1-mini used per-turn (S2S dictation) | 80 tok in | — | 500 tok out | $0.011 | **≈ $3.3** (weaker "brain" than a text frontier model) |

TTS is the largest line item, so offering text-only replies by default is the biggest single lever. Prompt caching (Claude cache reads ≈ 0.1× input) cuts the LLM line by ~50–70%.

### (ii) Heavy live-voice user: 600 min/mo

| Stack | Per-min | **$/mo** | Notes |
|---|---|---|---|
| **1. OpenAI gpt-realtime-2.1-mini** (direct) | ~$0.02–0.03 | **≈ $12–18 (mid $15)** | Best $/quality for live. Tail risk: long chatty sessions. Cap history / truncate |
| 1b. OpenAI gpt-realtime-2.1 | ~$0.07 (worst $0.15) | **≈ $42 (up to $88)** | Premium tier only |
| 1c. GPT-Live-1 + small backend | $0.05 + ~$0.005 | **≈ $33** | Most natural duplex. Backend could be Claude via our harness (unverified) |
| **2. Cascade (Pipecat): Deepgram Flux → Haiku 4.5 (OR) → Cartesia** | STT $0.0065 (all 600 min) + LLM ~$0.008 + TTS ~$0.0135 | **≈ $17** (Inworld TTS: ~$13; Sonnet 5: ~$22) | Any LLM incl. Claude, full control. ~0.9–1.3 s voice-to-voice (unverified) |
| **3. Gemini 3.1 Flash Live** | ~$0.02–0.06 | **≈ $12–36 (mid ~$21)** | Cheapest unit rates, but the whole context is re-billed each turn. Enable compression |
| 4. Grok Voice 2.0 / Ultravox / Hume | $0.08 / $0.05 / $0.04–0.07 | $48 / $30 / $24–42 | Flat-rate simplicity, higher cost |

**Pricing implication:** a flat ~$10–15/mo "unlimited" plan works for dictation users (COGS $2–5). It is **under water for heavy live users** on anything but realtime-mini. Meter live minutes: e.g. include 60–120 live min/mo and add a "Pro" tier (~$25–30 for ~600 min on mini). Or use soft-throttling or fair-use.

---

## 6. Recommendation

**Dictation mode (primary):**
- **Upload:** watch records the PTT clip as Opus (or AAC-LC via the native encoder) and uploads it with plain **HTTPS URLSession**, so no low-level-networking restriction applies. Our server responds with a streamed body (SSE/chunked).
- **STT:** Deepgram Nova-3 streaming, fed while the upload arrives, or `gpt-4o-mini-transcribe`. Groq Whisper-turbo is the cheap batch alternative.
- **LLM via OpenRouter, streaming SSE:** default **Claude Sonnet 5**, with a "fast" setting on **Haiku 4.5** or Gemini Flash. OpenRouter fallbacks cover provider outages.
- **TTS:** sentence-chunked streaming. Cartesia Sonic (best TTFB, PCM → we encode Opus) or `gpt-4o-mini-tts` (native Opus output, cheapest). Text-only reply is the default when the wrist is raised.

**Live mode (primary):** **OpenAI `gpt-realtime-2.1-mini`, direct WebSocket from our server.**
- The watch holds one WebSocket to us: Opus up and down, opened only inside an active audio session, per TN3135.
- Our server (Pipecat) transcodes Opus↔PCM16 24 kHz and runs the Realtime session with server VAD, barge-in and a capped history.
- Premium tier: `gpt-realtime-2.1` or GPT-Live-1.

**Live fallback, in order:**
1. **Gemini 3.1 Flash Live** (same Pipecat pipeline, provider swap). Fits also for multilingual users.
2. **Pipecat cascade**: Deepgram Flux → Haiku 4.5/Sonnet 5 via OpenRouter → Cartesia. Use it when the user picks "Claude" as the voice brain, or when both S2S vendors degrade.

**Where OpenRouter fits:** all text-LLM calls (dictation, cascade, summaries, titles, memory), model choice, fallbacks, one bill.

**Where it doesn't fit:**
- Realtime S2S. Nothing exists there.
- Lowest-latency streaming STT/TTS. Its audio endpoints are request/response.

Consider BYOK once one provider exceeds a few $k/mo. It's free up to $25k/mo, which also avoids the 5.5% fee.

**Codec and bitrate, watch ↔ server:**

| Leg | Codec | Settings | Data |
|---|---|---|---|
| Uplink (mic) | **Opus** | 16 kHz wideband, mono, VBR ~16 kbps (12 kbps on weak LTE), 20 ms frames, in-band FEC + DTX | ~2 KB/s ≈ 7 MB/hr |
| Downlink (voice) | **Opus** | 24 kHz, mono, ~24 kbps (32 max) | ~3 KB/s ≈ 11 MB/hr |
| Framing | binary WS frames | 20–60 ms packets (60 ms reduces overhead and radio wakeups on cellular) | — |

Why not the alternatives:
- **PCM16 at 24 kHz** is 384 kbps (~170 MB/hr per direction). Too heavy for watch LTE and battery.
- **G.711** is 64 kbps narrowband and hurts STT accuracy.
- **Dictation fallback:** AAC-LC 24–32 kbps at 16 kHz via the hardware encoder, if Opus encode on watchOS proves awkward. `kAudioFormatOpus` exists in CoreAudio, and the SwiftPM `swift-opus` supports watchOS, but on-device Opus *encode* performance is **unverified**.

**Open items to verify before build:**
1. Exact Gemini 3.1 Flash Live audio rates and whether context re-billing is cached.
2. Whether GPT-Live-1 allows a non-OpenAI backend (Claude).
3. Measured watch cellular RTT and Opus encode CPU/battery on Series 9+/Ultra.
4. Whether Realtime-2.1 accepts compressed input over WS (currently PCM/G.711 only, so we transcode).
5. Inworld/Rime Opus output.
