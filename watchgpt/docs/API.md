# WatchGPT Wire Protocol (v1)

The watch talks **only** to our gateway. Provider keys never touch the device.
Two transports, chosen because of watchOS networking rules (see `research/02-watchos-platform.md`):

| Mode | Transport | Why |
|---|---|---|
| **Turn** (push-to-talk / dictation / typed) | `POST` + streamed **NDJSON** response | Plain `URLSession` HTTPS works everywhere on watchOS, incl. cellular, with no audio-session preconditions. Read with `URLSession.bytes(for:)` → `.lines`. |
| **Live** (hands-free, full duplex) | **WebSocket** | Needs bidirectional low-latency audio. watchOS allows it only while the app holds an active audio session (TN3135). The client must `await AVAudioSession.activate()` *before* connecting, and must use **Network.framework** (`NWConnection` + `NWProtocolWebSocket`). `URLSessionWebSocketTask` is denied even then. |

Base URL: `https://api.<domain>` (dev: `http://localhost:8787`). All bodies UTF-8 JSON unless noted.

---

## 1. Auth: anonymous device accounts

No sign-up screen. First launch registers the device; the subscription (StoreKit) is attached later.

### `POST /v1/devices`
```json
// request (all optional)
{ "platform": "watchOS", "app_version": "0.1.0", "locale": "en-US" }
// 201 response
{ "device_id": "dev_7f3c…", "token": "wgpt_…", "plan": "trial",
  "limits": { "turns_per_day": 30, "live_seconds_per_month": 300 } }
```
Store `token` in the Keychain. Send it on every call as `Authorization: Bearer <token>`.

### `POST /v1/entitlements/apple` *(stubbed in prototype)*
`{ "signed_transaction": "<JWS from StoreKit 2 Transaction.jwsRepresentation>" }` → `{ "plan": "pro", "limits": {…} }`.
The server verifies the JWS against Apple's root CA and binds `originalTransactionId` → device account. Reinstalls and new watches restore through the same `originalTransactionId`.

### `GET /v1/me`
`{ "device_id", "plan", "limits", "usage": { "turns_today", "live_seconds_this_month" } }`

---

## 2. Turn mode: `POST /v1/turns`

### Request
Either **audio** or **text**:

```
POST /v1/turns?conversation_id=c_123&reply=voice
Authorization: Bearer wgpt_…
Content-Type: audio/mp4            ← AAC in .m4a from AVAudioRecorder (preferred)
                                     also: audio/wav, audio/webm, audio/mpeg
<raw audio bytes, ≤ 60 s, ≤ 2 MB>
```
```
POST /v1/turns
Content-Type: application/json
{ "conversation_id": "c_123", "text": "what's a good 20 minute dinner", "reply": "voice" }
```

| Param | Values | Default |
|---|---|---|
| `conversation_id` | client-generated or omitted (server creates one) | new |
| `reply` | `voice` (text + audio segments) · `text` (no TTS) | `voice` |
| `model` | `fast` (Claude Haiku 4.5) · `smart` (Claude Sonnet 5). The server maps aliases to real IDs | `fast` |

### Response: `200`, `Content-Type: application/x-ndjson`, one JSON event per line

```jsonc
{"type":"turn.started","turn_id":"t_…","conversation_id":"c_123"}
{"type":"transcript","text":"what's a good 20 minute dinner"}     // audio input only
{"type":"text.delta","text":"Try a "}                              // many
{"type":"audio.segment","seq":0,"format":"mp3","text":"Try a garlic shrimp stir-fry.","data":"<base64>"}
{"type":"text.delta","text":"…"}
{"type":"audio.segment","seq":1,"format":"mp3","text":"…","data":"<base64>"}
{"type":"turn.completed","turn_id":"t_…","text":"<full reply>","usage":{"input_tokens":412,"output_tokens":38,"audio_seconds_in":2.1}}
```
On failure mid-stream: `{"type":"error","code":"provider_unavailable","message":"…","retryable":true}`, then the stream closes.

**Audio segments are sentence-chunked, complete files.** Each `audio.segment` decodes to a standalone MP3/AAC file. The watch appends each to a queue of `AVAudioPlayer`s. This gives speech after about one sentence of LLM output, with no streaming-PCM decoder on the watch. `seq` is strictly increasing. Play in order.

### Errors before streaming (normal HTTP status + JSON)
| Status | `code` | Client behavior |
|---|---|---|
| 401 | `unauthorized` | re-register device |
| 402 | `quota_exceeded` | show paywall / "resets at" (`resets_at` field) |
| 413 | `audio_too_large` | cap recordings at 60 s |
| 415 | `unsupported_media_type` | — |
| 429 | `rate_limited` | back off `retry_after` s |

---

## 3. Live mode: `GET /v1/live` (WebSocket)

`wss://api.<domain>/v1/live?token=wgpt_…` (query-param token keeps clients simple; `NWProtocolWebSocket.Options.setAdditionalHeaders` with `Authorization` also works).

**Audio format both ways: raw PCM16 little-endian, mono, 24 kHz**, sent as **binary** frames of 20–100 ms (960–4800 bytes).
~48 KB/s up while talking. Acceptable on LTE. An Opus upgrade is planned (see ARCHITECTURE.md §6).

### Client → server (text frames, JSON)
| type | fields | meaning |
|---|---|---|
| `session.start` | `voice?`, `conversation_id?`, `vad?: "server"\|"manual"`, `resume_session_id?` | must be first frame. With `resume_session_id`, re-attaches to a live session that dropped less than `resume_window_s` ago |
| *(binary)* | PCM16 | mic audio |
| `input.commit` | — | manual VAD: "I'm done talking" (tap-to-send in live mode) |
| `response.cancel` | — | barge-in by tap. Server stops generating |
| `session.end` | — | graceful close, server flushes usage |

### Server → client
| type | fields | meaning |
|---|---|---|
| `session.ready` | `session_id`, `conversation_id`, `sample_rate: 24000`, `max_seconds`, `resume_window_s`, `resumed` | start streaming mic |
| *(binary)* | PCM16 | assistant audio. Enqueue to `AVAudioPlayerNode` |
| `speech.started` | — | user started talking. **Client must flush queued playback** (barge-in) |
| `speech.stopped` | — | VAD end of user speech |
| `transcript.user` | `text` | final user transcript |
| `transcript.assistant.delta` | `text` | streaming caption |
| `response.done` | `text` | assistant turn finished |
| `usage` | `live_seconds` | periodic, for the on-screen meter |
| `error` | `code`, `message` | e.g. `quota_exceeded` then close 4002 |

### Resume (required on watchOS)
watchOS revokes the audio-session networking grant (~36 s after `activate()`, FB24377808), and cellular handoffs drop sockets. So a dropped socket **does not end the session**:
1. The server keeps the upstream realtime session open for `resume_window_s` (15 s) after an unexpected close. It buffers assistant audio and events, up to 10 s of audio.
2. The client reconnects and sends `{"type":"session.start","resume_session_id":"ls_…"}` as its first frame.
3. The server replies `session.ready` with `resumed: true`, then flushes the buffered events and audio in order.
4. After the window, the session is closed and billed. A resume then gets a new session: `resumed: false`.

Only an explicit `session.end` (or quota/limit) ends a session immediately. Target reconnect time: < 1.5 s.

Close codes: `4001` unauthorized, `4002` quota exceeded, `4003` max session length, `4500` upstream failure.

---

## 4. Conversations

`GET /v1/conversations/:id` → `{ id, messages: [{role, text, at}] }`. The prototype keeps the last 20 messages in memory. The watch shows only the last few exchanges. History browsing belongs in an optional iPhone companion.

## 5. Health
`GET /healthz` → `{ ok: true, providers: { stt, llm, tts, live } }` (reports `mock` vs real per leg).
