# WatchGPT gateway (prototype)

This server is the only thing the watch talks to. It handles:
- device auth and quotas
- push-to-talk turns (streamed NDJSON)
- live voice (a WebSocket relay with resume)

The protocol is in [`../docs/API.md`](../docs/API.md).

It needs Node ≥ 22.18. TypeScript runs natively, with no build step.

```bash
npm install
npm start            # http://localhost:8787 (open it for the browser watch simulator)
npm test             # 11 end-to-end tests, offline (mock providers)
npm run typecheck
```

## Providers
Each leg (STT, LLM, TTS, live) runs on a **mock** unless its key is set, so everything works offline.

| Env | Effect |
|---|---|
| `ANTHROPIC_API_KEY` | LLM leg: Claude direct (`fast` = `claude-haiku-4-5`, `smart` = `claude-sonnet-5`) |
| `OPENROUTER_API_KEY` | LLM leg via OpenRouter, used if there's no Anthropic key or with `LLM_PROVIDER=openrouter` |
| `OPENAI_API_KEY` | STT (`gpt-4o-mini-transcribe`), TTS (`gpt-4o-mini-tts`), live (`gpt-realtime-2.1-mini`) |
| `STT_PROVIDER` / `LLM_PROVIDER` / `TTS_PROVIDER` / `LIVE_PROVIDER` | Force a leg: `mock`, `openai`, `anthropic`, `openrouter` |
| `MODEL_FAST`, `MODEL_SMART`, `LIVE_MODEL`, `TTS_VOICE`, `LIVE_VOICE` | Override model IDs and voices |
| `TOKEN_SECRET` | HMAC secret for device tokens (**required in prod**) |
| `RESUME_WINDOW_S` | How long a dropped live session waits for resume (default 15) |

`GET /healthz` shows which provider each leg is using.

## Simulator
Open `http://localhost:8787`:
- **Mic:** push-to-talk records webm and uploads it.
- **Text box:** stands in for watch dictation.
- **Live:** opens the WebSocket session. "Simulate network drop" tests resume.
- **Latency panel:** shows time to transcript, first text, first audio, and completion.
- **Wire events panel:** shows every protocol event.

With mock providers, the live mode echoes your own speech back, and the TTS is a chime sized to each sentence.

## Layout
```
src/server.ts        routing, static files, WS upgrade
src/turn.ts          STT → LLM → sentence chunker → parallel TTS, ordered NDJSON
src/live.ts          live session registry, resume buffer, metering
src/sentences.ts     speakable sentence chunking
src/store.ts         devices, tokens, usage, conversations (in-memory → Postgres/Redis)
src/providers/       mock.ts · anthropic.ts (SDK) · real.ts (OpenRouter, OpenAI STT/TTS/Realtime)
```

## Not production-ready yet
- In-memory storage.
- A stubbed StoreKit verification.
- No rate limiting.
- The live registry is per-process, so it needs Redis or sticky routing.

See `../docs/IMPLEMENTATION_PLAN.md`, milestone M1.
