// Real provider adapters. Each is a thin fetch/WebSocket wrapper so swapping
// vendors (Deepgram, Cartesia, Gemini Live, ...) is a one-file change.

import WebSocket from 'ws';
import { config } from '../config.ts';
import type { ChatMessage, LiveEvents, LiveProvider, LiveSession, LLMProvider, LLMUsage, STTProvider, TTSProvider } from './types.ts';
import { LIVE_SAMPLE_RATE } from './types.ts';

class ProviderError extends Error {
  code: string;
  retryable: boolean;
  constructor(code: string, message: string, retryable = true) {
    super(message);
    this.code = code;
    this.retryable = retryable;
  }
}
export { ProviderError };

async function ensureOk(res: Response, who: string) {
  if (res.ok) return;
  const body = await res.text().catch(() => '');
  throw new ProviderError('provider_error', `${who} ${res.status}: ${body.slice(0, 300)}`, res.status >= 500 || res.status === 429);
}

// ---------- STT: OpenAI transcriptions (accepts m4a/aac, wav, webm, mp3) ----------
const EXT: Record<string, string> = {
  'audio/mp4': 'm4a', 'audio/m4a': 'm4a', 'audio/x-m4a': 'm4a', 'audio/aac': 'm4a',
  'audio/wav': 'wav', 'audio/x-wav': 'wav', 'audio/webm': 'webm', 'audio/mpeg': 'mp3', 'audio/ogg': 'ogg',
};

export const openaiSTT: STTProvider = {
  name: 'openai',
  async transcribe(audio, mimeType) {
    const base = mimeType.split(';')[0].trim();
    const form = new FormData();
    form.append('model', config.sttModel);
    form.append('file', new Blob([new Uint8Array(audio)], { type: base }), `input.${EXT[base] ?? 'bin'}`);
    const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.openaiKey}` },
      body: form,
    });
    await ensureOk(res, 'stt');
    const json = (await res.json()) as { text: string };
    return { text: json.text };
  },
};

// ---------- LLM: OpenRouter chat completions (SSE) ----------
export const openrouterLLM: LLMProvider = {
  name: 'openrouter',
  async *stream(messages: ChatMessage[], { model, signal }) {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      signal,
      headers: {
        Authorization: `Bearer ${config.openrouterKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://watchgpt.app',
        'X-Title': 'WatchGPT',
      },
      body: JSON.stringify({ model, messages, stream: true, max_tokens: 400, usage: { include: true } }),
    });
    await ensureOk(res, 'llm');
    let usage: LLMUsage | undefined;
    const decoder = new TextDecoder();
    let buf = '';
    for await (const chunk of res.body as unknown as AsyncIterable<Uint8Array>) {
      buf += decoder.decode(chunk, { stream: true });
      let nl: number;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line.startsWith('data:')) continue; // skips ": OPENROUTER PROCESSING" keepalives
        const data = line.slice(5).trim();
        if (data === '[DONE]') return usage;
        const evt = JSON.parse(data);
        if (evt.error) throw new ProviderError('provider_error', `llm: ${evt.error.message ?? 'stream error'}`);
        const delta = evt.choices?.[0]?.delta?.content;
        if (delta) yield delta as string;
        if (evt.usage) usage = { input_tokens: evt.usage.prompt_tokens, output_tokens: evt.usage.completion_tokens };
      }
    }
    return usage;
  },
};

// ---------- TTS: OpenAI speech (one sentence -> one mp3) ----------
export const openaiTTS: TTSProvider = {
  name: 'openai',
  format: 'mp3',
  async synthesize(text, opts) {
    const res = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      signal: opts?.signal,
      headers: { Authorization: `Bearer ${config.openaiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: config.ttsModel,
        voice: config.ttsVoice,
        input: text,
        response_format: 'mp3',
        instructions: 'Warm, clear, brisk. Like a helpful friend speaking quietly.',
      }),
    });
    await ensureOk(res, 'tts');
    return Buffer.from(await res.arrayBuffer());
  },
};

// ---------- Live: OpenAI Realtime API (WebSocket, server-side relay) ----------
// Handles both GA event names (response.output_audio.delta) and the older
// beta names (response.audio.delta) so a model/API bump doesn't break us.
export const openaiLive: LiveProvider = {
  name: 'openai',
  connect({ instructions, voice, vad, history }, ev: LiveEvents): LiveSession {
    const ws = new WebSocket(`wss://api.openai.com/v1/realtime?model=${encodeURIComponent(config.liveModel)}`, {
      headers: { Authorization: `Bearer ${config.openaiKey}` },
    });
    const send = (obj: unknown) => ws.readyState === WebSocket.OPEN && ws.send(JSON.stringify(obj));
    const pending: Buffer[] = [];
    let assistantText = '';

    ws.on('open', () => {
      send({
        type: 'session.update',
        session: {
          type: 'realtime',
          instructions,
          audio: {
            input: {
              format: { type: 'audio/pcm', rate: LIVE_SAMPLE_RATE },
              transcription: { model: config.sttModel },
              turn_detection: vad === 'server' ? { type: 'semantic_vad', eagerness: 'high' } : null,
            },
            output: { format: { type: 'audio/pcm', rate: LIVE_SAMPLE_RATE }, voice },
          },
        },
      });
      // Seed recent text history so live mode continues the same conversation.
      for (const m of history.slice(-10)) {
        if (m.role === 'system') continue;
        send({
          type: 'conversation.item.create',
          item: { type: 'message', role: m.role, content: [{ type: m.role === 'user' ? 'input_text' : 'output_text', text: m.content }] },
        });
      }
      for (const b of pending.splice(0)) send({ type: 'input_audio_buffer.append', audio: b.toString('base64') });
      ev.onReady();
    });

    ws.on('message', (raw) => {
      const e = JSON.parse(raw.toString());
      switch (e.type) {
        case 'response.output_audio.delta':
        case 'response.audio.delta':
          ev.onAudio(Buffer.from(e.delta, 'base64'));
          break;
        case 'response.output_audio_transcript.delta':
        case 'response.audio_transcript.delta':
          assistantText += e.delta;
          ev.onAssistantDelta(e.delta);
          break;
        case 'input_audio_buffer.speech_started':
          ev.onSpeechStarted();
          break;
        case 'input_audio_buffer.speech_stopped':
          ev.onSpeechStopped();
          break;
        case 'conversation.item.input_audio_transcription.completed':
          ev.onUserTranscript(e.transcript ?? '');
          break;
        case 'response.done':
          ev.onResponseDone(assistantText);
          assistantText = '';
          break;
        case 'error':
          ev.onError('upstream_error', e.error?.message ?? 'realtime error');
          break;
      }
    });
    ws.on('error', (err) => ev.onError('upstream_unavailable', String(err)));
    ws.on('close', () => ev.onClose());

    return {
      sendAudio(pcm) {
        if (ws.readyState === WebSocket.CONNECTING) pending.push(pcm);
        else send({ type: 'input_audio_buffer.append', audio: pcm.toString('base64') });
      },
      commit() {
        send({ type: 'input_audio_buffer.commit' });
        send({ type: 'response.create' });
      },
      cancel() {
        send({ type: 'response.cancel' });
      },
      close() {
        ws.close();
      },
    };
  },
};
