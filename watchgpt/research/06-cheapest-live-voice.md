# 06 — Cheapest viable live voice stack (open-weight focus)

*Researched 2026-09-25. Builds on [03-inference-voice-stack.md](03-inference-voice-stack.md). That doc covers the proprietary S2S APIs and the Deepgram→Haiku→Cartesia cascade; this one doesn't repeat them. Prices are list/PAYG USD, seen 2026-09-25.*

> **Method caveat:** the sandbox proxy blocked almost every vendor and tracker site: openrouter.ai, deepinfra.com, together.ai, groq.com, baseten.co, alibabacloud.com, artificialanalysis.ai, huggingface.co, medium.com and daily.co.
> - **Everything is from 2026-dated search snippets, so treat it all as (secondary)** unless it's marked **(fetched)**. Only GitHub READMEs could be fetched directly.
> - **(unverified)** means an estimate of mine, or conflicting sources.
> - ★ marks numbers to re-check on the vendor page before committing.

---

## TL;DR

1. **Is "open models are much cheaper" true? Yes, by 10–25×, but mostly not for the reason the founder thinks.**
   - An **all-open hosted cascade costs ≈ $0.001–0.005 per conversation-minute**, vs **$0.02–0.03** for `gpt-realtime-2.1-mini` and **$0.015–0.06** for Gemini Flash Live.
   - The savings come from **(a)** replacing audio-token S2S billing with a text cascade, and **(b)** cheap open **TTS** (Kokoro at $0.62/M chars vs Cartesia at ~$30/M).
   - The open **LLM** saves only ~$0.002/min vs Claude Haiku 4.5 once prompt caching is on.
2. **There is no open S2S model we can buy per-minute and trust as a general assistant.**
   - Moshi and PersonaPlex are open and full-duplex, but they have 7B brains, no tools and English only.
   - The hosted "Qwen-Omni realtime" models are **closed-weight** Alibaba APIs. Qwen3.8-Omni-Flash (Sep 18 2026) ships **no weights**.
   - Ultravox has open weights, but its hosted API is a flat $0.05/min.
3. **OpenRouter still has no realtime/WebSocket endpoint** (re-checked, Sep 2026). It *can* now carry **all three cascade legs** as request/response calls:
   - Whisper-large-v3-turbo STT at **$0.00018/min**.
   - Any open LLM.
   - Kokoro at **$0.62/M chars** or Orpheus at **$7/M chars** TTS.
   That makes a vendor-independent, one-bill cascade possible, at the cost of ~150–300 ms of extra latency from batch STT.
4. **Self-hosting doesn't pay for a solo founder.**
   - Hosted open-model APIs (Groq, DeepInfra) already sell at close to GPU marginal cost.
   - A self-hosted cascade costs **≈ $0.005–0.009/min at 10 concurrent streams** and **≈ $0.003/min at 1,000**. Both are *more* expensive than the cheapest hosted open cascade (~$0.0015).
   - Self-hosting wins only against pricier hosted legs (Orpheus, streaming STT), and only at ≳1,000 concurrent streams (~30k heavy users).
5. **Recommendation:** build a **"cascade" `LiveProvider`** in our gateway: Silero VAD + smart-turn v3 → Whisper-turbo → **gpt-oss-120b** → **Kokoro**.
   - Route the STT, LLM and TTS legs through **OpenRouter**, with a streaming-STT adapter as the latency upgrade.
   - Cost: **≈ $0.0015–0.005/min**, i.e. **~$0.1–0.3 per 60-min user and ~$1–3 per 600-min user per month**.
   - Keep `gpt-realtime-2.1-mini` as the premium "most natural" mode.

---

## 1. Open speech-to-speech / audio-native models (Sep 2026)

| Model | Type | License | Quality as a general assistant | Latency | Hosted API ($/min) | Self-host GPU |
|---|---|---|---|---|---|---|
| **Kyutai Moshi** (7B) | Full-duplex S2S | Code MIT/Apache; weights CC-BY-4.0 (unverified) | Weak: 7B "Helium" brain, no tools, EN/FR. A fun demo, not an assistant. No open Meta/Llama S2S model found (unverified) | ~200 ms theoretical | None commercial found | 1× 24 GB GPU |
| **NVIDIA PersonaPlex-7B** (Jan 2026) | Full-duplex S2S, Moshi-based | Code MIT; weights NVIDIA Open Model License **(fetched)** | English only. Trained on customer-service and casual chat. **No tool calling (fetched)** | 0.07 s speaker switch, "18× lower than Gemini Live" (vendor) | None | ≥16–24 GB (RTX 4090/A100) |
| **Kyutai Unmute** | Open **cascade** wrapper (STT 1B/2.6B + TTS 1.6B + any LLM) | STT/TTS weights CC-BY-4.0 (unverified) | As good as the LLM you plug in. **Kyutai's production uses gpt-oss-120b via OpenRouter (fetched)** | ~450 ms TTS on multi-GPU, ~750 ms on one L40S (fetched) | None | 16 GB min; 64 STT streams/L40S, 400/H100 (secondary) |
| **Ultravox v0.7** | Speech-in → text-out (needs a TTS) | Open weights on HF, MIT (unverified) | Strong: GLM-4.6 355B backbone | good | **Ultravox Realtime $0.05/min** all-in, 30 free min | GLM-4.6 needs a multi-H100 node. 8B/70B variants on 1–2 GPUs (Baseten library has v0.6 70B) |
| **Qwen3-Omni-30B-A3B** (open) | Speech in/out ("Thinker-Talker") | Apache-2.0 | Decent: 30B MoE, 3B active | TTFT ~215 ms (Thinking, vLLM) | Novita $0.25/$0.97 per M tokens (speech-out support unverified). Alibaba | 1× H100/A100-80GB BF16; AWQ-4bit on 24–48 GB |
| **Qwen3/3.5-Omni-Flash-Realtime, Qwen3.8-Omni-Flash-Realtime** (DashScope) | Realtime WS S2S | **Closed weights, API only** | Good | good | Token-billed. Audio in ≈ $3.81/M (Sg). Qwen3.8 claims "<$0.01/hr audio in". **Est. $0.01–0.03/min (unverified, sources conflict)** | n/a |
| **Qwen Audio 3.1 Realtime Plus** | Realtime WS S2S | Closed | Good | — | $12.80/M audio in, **$48/M audio out**, so pricier than Flash | n/a |
| **Step-Audio 2 mini** (8B) / StepAudio 2.5 Realtime | S2S | mini: Apache-2.0. 2.5 Realtime: closed API (`wss://api.stepfun.com/v1/realtime`) | mini is OK; 2.5 targets roleplay | — | StepFun price not found | 1× 24–48 GB |
| **MiniCPM-o 4.5** (9B, Qwen3-8B brain) | Full-duplex omni | Apache-2.0 (secondary; older MiniCPM had a custom license, so check) | 8B brain | "low" | None | 1× 24 GB |
| **GLM-4-Voice**, **Sesame CSM-1B** | GLM-4-Voice: S2S (2024). CSM: **TTS only** | GLM-4-Voice: custom (unverified). CSM: Apache-2.0 | Dated / TTS only. The Sesame "Maya" demo model is *not* open | — | — | — |
| **PhoneLLM Alpha 1** (Pipecat, Aug 2026) | **Text** LLM tuned for voice agents (Nemotron 3 Nano 30B-A3B FT) | BSD-2 | Tuned for tool calls without reasoning. **Phone-agent focus, not general knowledge** | P95 TTFT <100 ms single / <600 ms loaded on B200 | Modal AutoEndpoint, Featherless | 88 sessions per B200 node (vendor) |

**Verdict:**
- Open full-duplex S2S (Moshi, PersonaPlex, MiniCPM-o) is **real but not assistant-grade**: small brains, no tools, English only. Research releases like JoyAI-Talker and Raon-Speech exist too.
- The hosted Qwen realtime APIs are cheap but **not open**. They are also a Chinese-cloud dependency; the Singapore/US-Virginia regions exist.
- **For "open + answers well," a cascade beats any open S2S model today.**

Sources: [Kyutai](https://kyutai.org/) · [Unmute README (fetched)](https://github.com/kyutai-labs/unmute/blob/main/README.md) · [Unmute concurrency (secondary)](https://github.com/kyutai-labs/delayed-streams-modeling/) · [PersonaPlex repo (fetched)](https://github.com/NVIDIA/personaplex) · [PersonaPlex latency (WinBuzzer)](https://winbuzzer.com/2026/01/27/nvidia-personaplex-open-source-voice-ai-full-duplex-xcxwbn/) · [Ultravox v0.7 blog](https://www.ultravox.ai/blog/introducing-ultravox-v0-7-the-world-s-smartest-speech-understanding-model) · [Ultravox pricing](https://www.ultravox.ai/pricing) · [Baseten Ultravox 70B](https://www.baseten.co/library/ultravox-v0-6-70b/) · [Qwen3-Omni HF](https://huggingface.co/Qwen/Qwen3-Omni-30B-A3B-Instruct) · [Novita Qwen3-Omni](https://novita.ai/models/model-detail/qwen-qwen3-omni-30b-a3b-instruct?from=pricing) · [Qwen3.8-Omni-Flash, no weights (Startup Fortune)](https://startupfortune.com/alibabas-qwen38-omni-flash-slashes-audio-pricing-98-and-drops-open-weights/) · [MarkTechPost 2026-09-18](https://www.marktechpost.com/2026/09/18/alibaba-qwen-releases-qwen3-8-omni-flash/) · [aireiter Qwen3.8 rate card](https://aireiter.com/blog/qwen3-8-omni-flash-api-pricing) · [Qwen Audio 3.1 Realtime Plus](https://empiriolabs.ai/models/qwen-audio-3-1-realtime-plus) · [Step-Audio2](https://github.com/stepfun-ai/Step-Audio2) · [StepAudio 2.5 Realtime](https://www.marktechpost.com/2026/05/24/stepfun-releases-stepaudio-2-5-realtime-an-end-to-end-voice-model-with-roleplay-specific-rlhf-and-paralinguistic-comprehension/) · [MiniCPM-o](https://github.com/OpenBMB/MiniCPM-o?tab=readme-ov-file) · [Sesame CSM](https://github.com/SesameAILabs/csm) · [PhoneLLM announcement](https://www.daily.co/blog/announcing-pipecat-phonellm-alpha-1/) · [PhoneLLM deploy/cost (MindStudio)](https://www.mindstudio.ai/blog/phonellm-cost-per-minute-voice-agents) · [PhoneLLM example (fetched)](https://github.com/pipecat-ai/pipecat-examples/tree/main/phonellm)

---

## 2. Open cascade components: cheapest hosted price

### Cost model (applies to every $/min in this doc)
One **conversation-minute** splits into 40% user speech (24 s), 40% assistant speech (24 s) and 20% silence. At ~150 wpm that is ~60 assistant words ≈ **360 characters of TTS per minute**. There are ~3 LLM turns/min at ~2,500 input tokens each (system + history), which is **7,500 input + 120 output tokens per minute**.
- **Streaming STT** is billed on the full 60 s, because it needs the mic open for barge-in.
- **Batch STT**, gated by our VAD, is billed on ~30 s.

### 2a. STT

| Model (license) | Streaming? | Cheapest hosted | $/conv-min | Notes |
|---|---|---|---|---|
| **Whisper-large-v3-turbo** (MIT) | **Batch only** on Groq, DeepInfra and OpenRouter | **OpenRouter/DeepInfra $0.000003/s = $0.00018/min** ★. Groq $0.04/hr = $0.00067/min | **$0.0001** (VAD-gated) | Transcribe each endpointed utterance. Adds ~150–300 ms after end-of-turn (unverified) |
| Whisper-large-v3 **streaming** (MIT) | **Yes, WebSocket** (Together) | Together $0.0015/min (secondary) | $0.0015 | Together advertises built-in VAD/turn detection |
| Whisper on Fireworks | Batch + streaming | $0.0009–0.0015 batch; **$0.0032/min streaming** (secondary) | $0.0032 | — |
| **Parakeet-TDT-0.6B-v3** (CC-BY-4.0) | Batch (hosted) | OpenRouter $0.000025/s = $0.0015/min | $0.0008 | 25 EU languages |
| **Nemotron Speech Streaming 0.6B / Nemotron-3.5-ASR-Streaming** (NVIDIA Open Model Lic.) | **True cache-aware streaming**, 80 ms–1 s chunks | Self-host / NVIDIA NIM | — | **560 streams/H100 @320 ms**. v3.5: 240–2,400 streams/H100, 40 languages |
| **Kyutai STT 1B/2.6B** (CC-BY-4.0, unverified) | Streaming + semantic VAD | Self-host | — | 64 streams/L40S, 400/H100 |
| *Ref: Deepgram Flux / Soniox / AssemblyAI (closed)* | Streaming | $0.0065 / $0.002 / $0.0025 per min | — | From doc 03 |

### 2b. LLM (reasoning off / `reasoning_effort: low` on the live path)

| Model (open?) | Host | $ in / out per M | **$/conv-min** | Speed / TTFT |
|---|---|---|---|---|
| **gpt-oss-20b** (Apache-2.0) | Groq | $0.075 / $0.30 | **$0.0006** | ~900–1,000 tok/s. p95 TTFT 0.38 s (secondary) |
| **gpt-oss-120b** (Apache-2.0) | Groq | $0.15 / $0.60 | **$0.0012** | Median TTFT 234 ms (OpenRouter data, doc 03) |
| gpt-oss-120b | Cerebras | $0.35 / $0.75 | $0.0027 | >2,000 tok/s |
| GLM-5.3-Flash (open status unverified) | OpenRouter | $0.045 / $0.14 | $0.0004 | unverified |
| Qwen3.8 Flash (weights for "Flash-Next" released Aug 2026, unverified) | OpenRouter | $0.15 / $0.47 | $0.0012 | unverified |
| DeepSeek V3.2 (MIT) | OpenRouter | $0.21 / $0.31 | $0.0016 | Often slow TTFT on shared providers (unverified) |
| Llama 4 Maverick | Groq | $0.50 / $0.77 | $0.0038 | Groq moved Llama 3.x to enterprise-only (Aug 26 2026) |
| Kimi K2.6 | OpenRouter | $0.50 / $2.97 | $0.0041 | Large, slower |
| *Ref: Claude Haiku 4.5 (closed)* | OpenRouter | $1 / $5 | **$0.008 uncached → ~$0.002–0.003 with caching** | TTFT ~0.6 s |
| *Ref: Claude Sonnet 5 (closed)* | OpenRouter | $2 / $10 | $0.016 → ~$0.005 cached | — |

The OpenRouter 5.5% credit fee is negligible at these amounts.

### 2c. TTS (360 chars per conv-min)

| Model (license) | Hosted price / M chars | **$/conv-min** | Streaming TTFB | Formats | Quality (AA Speech Arena Elo, Sep 2026) |
|---|---|---|---|---|---|
| **Kokoro-82M** (Apache-2.0) | **$0.62 OpenRouter (DeepInfra/Together)** ★. DeepInfra ~$0.80. Together direct $4 after a 60% cut on 2026-07-29 | **$0.0002** | Fast. RTF ~0.02–0.05 on a 4090 | DeepInfra: mp3/**opus**/flac/wav/pcm. OpenRouter: mp3/pcm | **~1063**: clean but flatter, clearly "TTS-sounding" |
| **Orpheus 3B** (Llama-3.2 base, so the Llama license applies, unverified) | **OpenRouter $7** (provider unverified). Together $15. **Groq $22** | $0.0025 / $0.0054 / $0.0079 | Groq <200 ms. Baseten <150 ms on a full H100 | Groq: wav/mp3/flac/ogg/mulaw, 24 kHz | Expressive (laughs, sighs). Mid-pack |
| **Qwen3-TTS 1.7B** (Apache-2.0) | Baseten dedicated ≈ $3–4/M. Self-host ≈ $2/M on H100 | ~$0.0012 | **<50 ms p95 TTFA** (Baseten), input-streaming | PCM | Good. The hosted "Qwen-Audio-3.x-TTS" versions are *closed* |
| Kyutai TTS 1.6B (CC-BY-4.0, unverified) | Self-host only | — | Text-streaming input, built for LLM output | PCM | Good EN/FR |
| Chatterbox / Turbo (MIT) | Replicate, Resemble (price unverified) | — | ~75 ms model, <200 ms streaming | wav | Good. Voice cloning |
| NVIDIA Magpie-Multilingual 357M | NIM / self-host | — | Low | PCM | 1063 |
| **Breeze TTS 2** | $34/M hosted | $0.012 | 134 ms p50, WS | — | **1205–1215, best open**, but the **weights are non-commercial** |
| Fish S2 Pro / S2.1 Pro | $15/M. S2.1 "free" dev tier (fair use, no SLA) | $0.0054 | — | — | 1122. **Weights research-only** |
| Voxtral TTS (Mistral) | $16/M, also on OpenRouter | $0.0058 | ~90 ms | — | 1078. **Weights CC-BY-NC** |
| *Ref: Cartesia Sonic-3.6 (closed)* | ~$30/M | $0.011 | ~90 ms | PCM | **1279, top overall** |

**Open-TTS licensing trap:** the best-sounding "open" TTS models (Breeze 2, Fish S2, Voxtral) are **non-commercial**. They are commercially usable only through their vendor's API, which brings the lock-in back. Commercially clean open options are Kokoro, Qwen3-TTS, Chatterbox, Orpheus (Llama license), Kyutai and Magpie.

### 2d. VAD and turn detection (free, runs in our gateway)
- **Silero VAD** (MIT): ~1 ms/frame on CPU. Runs in Node via `onnxruntime-node`.
- **Pipecat smart-turn v3** (BSD-2, ONNX): **~12 ms on CPU**, <500 MB RAM. It runs only during silences, to decide whether the user has finished. Also runs in `onnxruntime-node` or a Pipecat sidecar.
- **LiveKit turn detector**: open weights, but a text-based model tied to the LiveKit Agents runtime. Less useful for us.
- Barge-in means: VAD fires → gateway sends `speech.started` → cancel the LLM and TTS streams. The API.md §3 events already model this.

Sources: [OpenRouter Whisper-turbo](https://openrouter.ai/openai/whisper-large-v3-turbo) · [Parakeet vs Whisper (OR)](https://openrouter.ai/compare/nvidia/parakeet-tdt-0.6b-v3/openai/whisper-large-v3-turbo) · [Together Whisper streaming](https://www.together.ai/models/whisper-large-v3-streaming) · [Fireworks STT (futureagi)](https://futureagi.substack.com/p/speech-to-text-apis-in-2026-benchmarks) · [Nemotron ASR scaling](https://huggingface.co/blog/nvidia/nemotron-speech-asr-scaling-voice-agents) · [Nemotron 3.5 ASR](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) · [Groq pricing (CloudZero)](https://www.cloudzero.com/blog/groq-pricing/) · [Groq free tier/Llama change](https://klymentiev.com/blog/groq-pricing) · [gpt-oss-20b providers](https://artificialanalysis.ai/models/gpt-oss-20b/providers) · [Cerebras pricing (Morph)](https://www.morphllm.com/cerebras-pricing) · [OpenRouter DeepSeek V3.2](https://openrouter.ai/deepseek/deepseek-v3.2) · [OR GLM-5.3-Flash](https://openrouter.ai/z-ai/glm-5.3-flash) · [OR Qwen3.8 Flash](https://openrouter.ai/qwen/qwen3.8-flash) · [OR Kimi K2.6](https://openrouter.ai/moonshotai/kimi-k2.6) · [Haiku TTFT (layer3labs)](https://www.layer3labs.io/guides/best-llm-for-voice-agents) · [OR Kokoro](https://openrouter.ai/hexgrad/kokoro-82m) · [OR TTS collection](https://openrouter.ai/collections/text-to-speech-models) · [Together Kokoro price cut](https://www.together.ai/models/kokoro-82m) · [DeepInfra TTS formats](https://docs.deepinfra.com/apis/text-to-speech) · [Groq Orpheus $22/M](https://www.adwaitx.com/groq-canopy-orpheus-tts-groqcloud-launch/) · [Groq TTS formats (Pipecat)](https://docs.pipecat.ai/api-reference/server/services/tts/groq) · [Baseten Orpheus](https://www.baseten.co/library/orpheus-tts/) · [Baseten Qwen3-TTS](https://www.baseten.co/blog/cost-efficient-high-performance-qwen3-tts/) · [AA open-weights TTS board](https://artificialanalysis.ai/text-to-speech/leaderboard/provider-voice/open-weights) · [Breeze TTS 2 license](https://www.mindstudio.ai/blog/breeze-tts-2-license-commercial-use) · [Fish S2 Pro](https://huggingface.co/fishaudio/s2-pro) · [Fish S2.1 free](https://fish.audio/blog/s2-1-pro-free-api/) · [Voxtral TTS](https://mistral.ai/news/voxtral-tts/) · [Chatterbox Turbo](https://www.resemble.ai/learn/models/chatterbox-turbo) · [smart-turn](https://github.com/pipecat-ai/smart-turn) · [Smart Turn v3 12 ms](https://www.daily.co/blog/announcing-smart-turn-v3-with-cpu-inference-in-just-12ms/) · [LiveKit turn detector](https://docs.livekit.io/agents/logic/turns/turn-detector/)

---

## 3. OpenRouter re-check (Sep 2026)

| Capability | Status |
|---|---|
| Realtime / WebSocket / full-duplex | ❌ Still none (2026-dated guide: "no documented realtime WebSocket API"). Not usable for S2S |
| `/api/v1/audio/transcriptions` | ✅ Open models routed: **Whisper-large-v3-turbo $0.00018/min** (DeepInfra, Groq), **Parakeet-TDT-0.6B-v3 $0.0015/min**. File upload, **not streaming** |
| `/api/v1/audio/speech` | ✅ Open models routed: **Kokoro-82M $0.62/M chars** (DeepInfra, Together) and **Orpheus 3B $7/M**. Also Voxtral Mini TTS, Qwen-Audio-3.x-TTS, gpt-4o-mini-tts, Gemini TTS, and **Fish S2.1 Pro `:free`**. OpenAI-compatible; returns a raw byte stream, `response_format` = `pcm` (default) or `mp3`. PCM is what our relay wants |

**Implication:** all three cascade legs can go through one vendor-neutral key. The cost is batch STT (latency) and one TTS request per sentence.

Sources: [OR audio APIs blog](https://openrouter.ai/blog/announcements/announcing-audio-apis/) · [OR TTS docs](https://openrouter.ai/docs/guides/overview/multimodal/tts) · [OR speech API ref](https://openrouter.ai/docs/api/api-reference/tts/create-audio-speech) · [Realtime gap (crazyrouter guide)](https://crazyrouter.com/en/blog/openai-realtime-api-complete-guide-2026) · [Fish S2.1 free on OR](https://openrouter.ai/fish-audio/s2.1-pro-free:free)

---

## 4. Self-hosting economics

**GPU prices** (Sep 2026, secondary):
- **Modal** (per-second, serverless): L4 $0.80/hr, A10 $1.10, **L40S $1.95**, A100-80 $2.50, **H100 $3.95**, B200 $6.25.
- **RunPod**: L4 $0.44, **L40S $1.09** (community), **H100 $1.99–2.99**, serverless H100 ~$4.55.

**Concurrency per GPU** (vendor/secondary; the LLM figure is unverified):

| Leg | Model | Streams per GPU |
|---|---|---|
| STT | Nemotron streaming | 560 per H100 |
| STT | Kyutai | 64 per L40S |
| TTS | Kokoro | 50+ per A100 |
| TTS | Orpheus | 16–25 per H100 |
| LLM | 20–30B-A3B MoE (gpt-oss-20b, PhoneLLM) | ~40–50 sessions per H100 at <600 ms P95 TTFT (from Pipecat's 88 sessions/B200 node) |

**The LLM is the bottleneck.** Load model: peak concurrency ≈ users × 20 min/day × 10% in the peak hour ÷ 60. So **10 concurrent ≈ 300 heavy users ≈ 180k min/mo**.

| Scale (peak concurrent) | Fleet (always-on; one open cascade: Kyutai/Nemotron STT + Kokoro + gpt-oss) | $/mo | Minutes/mo | **$/conv-min** |
|---|---|---|---|---|
| **10** (~300 heavy users) | 1× L40S does everything, Unmute-style (+1 spare for HA) | RunPod $800–1,600. Modal $1,400–2,850 | 180k | **$0.0045–0.016** |
| **100** (~3k) | 1× H100 STT+TTS, 3× H100 LLM, 1 spare, ~$2.5/hr | ~$9.1k | 1.8M | **~$0.005** |
| **1,000** (~30k) | ~2 STT + ~6 TTS + ~22 LLM H100s, reserved ~$2/hr | ~$44–51k | 18M | **~$0.0025–0.003** |

**Break-even:**
- **vs `gpt-realtime-2.1-mini` ($0.025/min):** a single $800/mo GPU pays for itself at ~32k min/mo, about 55 heavy users. *But the hosted open cascade beats realtime-mini from user #1 with zero ops.*
- **vs hosted cheapest open cascade (~$0.0015/min):** self-hosting **never wins** at the scales in the table. Groq and DeepInfra already price near GPU marginal cost with better multiplexing.
- **vs hosted "good-voice" open cascade (streaming STT + Orpheus, ~$0.005–0.011/min):** self-hosting wins from ~100 concurrent. At 1,000 concurrent it saves ~$0.002–0.008/min, i.e. **$36k–140k/mo**. That is the point to revisit it.
- **Solo-founder ops burden:** GPU capacity planning, CUDA/vLLM upgrades, cold starts (Modal), multi-region latency, and on-call for a real-time path. Real, and mostly avoidable until ~1,000 concurrent. Middle path: a **Modal/Baseten dedicated deployment of a single leg** that has no good hosted API (e.g. Qwen3-TTS or Kyutai STT).

Sources: [Modal GPU rates (Spheron)](https://www.spheron.network/blog/modal-gpu-pricing-2026-per-second-billing/) · [RunPod pricing (Spheron)](https://www.spheron.network/blog/runpod-h100-pricing-2026/) · [RunPod L4/L40S (gpuperhour)](https://gpuperhour.com/providers/runpod) · [Self-hosted voice stack crossover (layer3labs)](https://www.layer3labs.io/guides/self-hosted-voice-agent-stack) · [voice-cost-bench, L40S, rates 2026-09-17 (fetched)](https://github.com/asadrizv/voice-cost-bench) · [Nemotron voice agent blueprint, 64 streams on 4×H100](https://github.com/NVIDIA-AI-Blueprints/nemotron-voice-agent) · [Kokoro GPU sizing (Spheron)](https://www.spheron.network/blog/deploy-open-source-tts-gpu-cloud-2026/) · [PhoneLLM B200 math (MindStudio)](https://www.mindstudio.ai/blog/phonellm-cost-per-minute-voice-agents)

---

## 5. Comparison table

The cost model is in §2. Every row also carries our gateway (Opus/PCM relay, VAD, orchestration), ~$0.0003/min (unverified), which is not included. Voice-to-voice latency is measured from end of user speech to first audio at our server, excluding watch radio time, and is **estimated (unverified)** unless noted.

| # | Stack | Open? | Vendor lock | **$/conv-min** | V2V latency | Quality notes | Works with our WS PCM16 relay? |
|---|---|---|---|---|---|---|---|
| a | **OpenAI gpt-realtime-2.1-mini** (doc 03) | No | High (OpenAI) | **$0.020–0.030** | ~0.5–0.9 s | Most natural duplex, good brain, tools | ✅ server-side WS, PCM16 24 kHz native |
| b | **Gemini 3.1 Flash Live** (doc 03) | No | High (Google) | **$0.015–0.06** (context re-billed) | ~0.6–1.0 s | Good. 15-min sessions | ✅ resample to 16 kHz in |
| c | **Cheapest all-open hosted cascade:** VAD+smart-turn → Whisper-turbo batch (DeepInfra) → gpt-oss-20b (Groq) → Kokoro (DeepInfra) | **Yes** (all weights) | Low (each leg has 2+ hosts) | **≈ $0.0009** (STT $0.0001 + LLM $0.0006 + TTS $0.0002) | ~0.9–1.5 s | Kokoro sounds "TTS-ish". The 20B brain is fine for chit-chat and weak on facts | ✅ we own the pipeline; Kokoro PCM out |
| c2 | **"Sounds good" open hosted:** Together Whisper *streaming* → gpt-oss-120b (Groq) → Orpheus (OR $7 / Groq $22) | Yes | Low–med | **≈ $0.005–0.011** | ~0.8–1.2 s | Expressive voice, better brain | ✅ |
| d | **Open cascade, all legs via OpenRouter:** Whisper-turbo → gpt-oss-120b (pinned to Groq/Cerebras) → Kokoro | Yes | **Lowest** (one key, provider fallback) | **≈ $0.0015** | ~1.0–1.6 s (batch STT, per-sentence TTS, +25–40 ms/hop) | Same as c, better brain | ✅ `pcm` response_format |
| d′ | Same, but **Claude Haiku 4.5** as the brain (cached) | STT/TTS open | Low | **≈ $0.003–0.009** | ~1.1–1.7 s | Best answers per $. Still Kokoro voice | ✅ |
| e1 | **Ultravox Realtime** (hosted; open weights) | Weights yes, service no | Med | **$0.05** | ~0.6–1.0 s | GLM-4.6 brain, strong | ✅ WS (format unverified) |
| e2 | **Qwen-Omni-Flash-Realtime** (DashScope) | **No** (closed Flash weights) | High (Alibaba) | **~$0.01–0.03 (unverified)** | good | Good, multilingual | ✅ WS, PCM (unverified) |
| f10 | Self-hosted open cascade, **10 concurrent** | Yes | None (you own it) | **$0.0045–0.016** | ~0.6–1.0 s colocated (Unmute: ~0.75 s TTS on 1 L40S) | Same models as c | ✅ |
| f100 | Self-hosted, **100 concurrent** | Yes | None | **~$0.005** | ~0.6–0.9 s | — | ✅ |
| f1000 | Self-hosted, **1,000 concurrent** | Yes | None | **~$0.0025–0.003** | ~0.6–0.9 s | — | ✅ |

## 6. Monthly cost per user

| Stack | 60 min/mo | 600 min/mo |
|---|---|---|
| a. gpt-realtime-2.1-mini | $1.20–1.80 | **$12–18** |
| b. Gemini 3.1 Flash Live | $0.90–3.60 | $9–36 |
| c. Cheapest all-open hosted | **$0.05** | **$0.54** |
| c2. "Sounds good" open hosted | $0.30–0.66 | $3.0–6.6 |
| d. All-OpenRouter open cascade | $0.09 | $0.90 |
| d′. OpenRouter open STT/TTS + Claude Haiku (cached) | $0.18–0.54 | $1.8–5.4 |
| e1. Ultravox | $3.00 | $30 |
| e2. Qwen-Omni realtime (closed) | $0.60–1.80 | $6–18 |
| f. Self-host @10 / 100 / 1,000 concurrent | $0.27–0.96 / $0.30 / $0.15–0.18 | $2.7–9.6 / $3.0 / $1.5–1.8 |

---

## 7. Recommendation

**Default live mode: the open cascade behind our own `LiveProvider`.** It is roughly 10–15× cheaper than realtime-mini at acceptable quality.

| Leg | Choice | Route | $/conv-min |
|---|---|---|---|
| VAD / turn | Silero VAD + smart-turn v3 (ONNX) | In the gateway (Node `onnxruntime-node` or a Pipecat sidecar) | $0 |
| STT | Whisper-large-v3-turbo | **OpenRouter** `/audio/transcriptions`, per endpointed utterance | $0.0001 |
| LLM | **gpt-oss-120b**, `reasoning_effort: low`, provider pinned to Groq with Cerebras fallback. A/B it against **Claude Haiku 4.5** (same OpenRouter key; +~$0.002/min cached) | **OpenRouter** | $0.0012 |
| TTS | Kokoro-82M `pcm` for sentence 1 while the LLM streams. Premium-voice flag: Orpheus ($7/M) or Cartesia (doc 03) | **OpenRouter** `/audio/speech` | $0.0002 |
| **Total** | | | **≈ $0.0015 (~$0.9 per 600-min user)** |

- **Latency upgrade path, if p50 V2V > 1.2 s:** swap STT to a *streaming* adapter. Options: Together Whisper streaming at $0.0015, Deepgram Flux at $0.0065, or self-hosted Nemotron/Kyutai on one Modal GPU. The STT leg is the only one where OpenRouter's request/response model really hurts.
- **Premium "most natural" mode:** `gpt-realtime-2.1-mini` via the existing `openaiLive`, metered. **Skip** open S2S (Moshi, PersonaPlex, MiniCPM-o): not assistant-grade. **Skip** Ultravox: $0.05/min is 30× the open cascade.

**Staying vendor-independent.** All three cascade legs go through OpenRouter, so there is one key plus provider fallback. Only realtime S2S and streaming STT need direct vendors. Changes in `server/src/providers/` (proposal only; nothing edited):
1. **Add a `cascadeLive: LiveProvider`.** It composes `STTProvider` + `LLMProvider` + `TTSProvider` + VAD/turn detection and emits the same `LiveEvents`. The watch protocol (API.md §3) stays unchanged. Register it as `live: { mock, openai, cascade }`.
2. **Add `openrouterSTT` and `openrouterTTS`** next to `openrouterLLM`. `TTSProvider.format` needs a `'pcm16'` option (today it only allows `mp3|aac|wav`), so sentence audio can go straight into the PCM relay.
3. **Add an optional `StreamingSTTProvider`** interface (`push(pcm)`, `onPartial`, `onFinal`) for Together, Deepgram or self-hosted Nemotron. That is the one leg OpenRouter can't serve well.
4. **Keep model IDs in config** (`openai/gpt-oss-120b`, `anthropic/claude-haiku-4.5`, `hexgrad/kokoro-82m`). Switching the brain or the voice is then a config change, not code.

**Is "open models are much cheaper" true for voice?**
- **Yes:** ~$0.001–0.005/min vs $0.02–0.03 for realtime-mini, i.e. **10–25×**.
- **But the saving comes mostly from the cascade architecture and open TTS, not from the open LLM.**
  - Swapping Haiku (cached) for gpt-oss-120b saves only ~$0.001–0.002/min, about $1/mo for a heavy user.
  - Swapping Cartesia for Kokoro saves ~$0.011/min, about $6.5/mo.
- **"Self-host open models to save more" is false at our scale.** Hosted open APIs are cheaper than our own GPUs until ~1,000 concurrent streams.

**Quality trade-offs:**
- **Voice:** Kokoro is clear but noticeably less natural than Sonic-3.6 or realtime-mini. Elo is ~1063 vs 1279. It doesn't do emotion, laughter or overlap.
  - The open models that close the gap (Breeze 2 at 1205, Fish S2) are **non-commercial** as weights.
  - Orpheus and Qwen3-TTS are the commercially clean middle ground.
- **Brain:**
  - gpt-oss-120b is good at chit-chat, short tasks and tools. It is weaker than Claude Haiku/Sonnet on factual recall, nuance and long-context instruction-following (general impression, unverified for our prompts).
  - gpt-oss-20b is noticeably weaker still.
  - For a general assistant, **run an eval on ~50 real watch queries** before settling the default. Haiku costs only ~$1/mo more per heavy user.
- **Conversational feel:**
  - A cascade is half-duplex with barge-in: no backchannels, no talking over each other.
  - It has ~0.3–0.6 s more latency than S2S.
  - On a wrist, with short turns, this is acceptable. For "chatty companion" use, realtime-mini stays the premium tier.

**Open items:**
1. Measure OpenRouter Whisper-turbo and Kokoro round-trip latency from our region.
2. Confirm the OpenRouter provider for Orpheus at $7/M ★.
3. Pin down the exact audio token rates for Qwen-Omni realtime; sources conflict ★.
4. Check gpt-oss-120b TTFT on Groq with `reasoning_effort: low`. The Artificial Analysis "3 s to first answer token" figure is measured with reasoning on.
5. Check echo cancellation on watchOS in live mode (voiceChat AVAudioSession mode), since our VAD will hear the TTS.
