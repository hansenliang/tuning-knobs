// Deterministic offline providers. They exercise every code path of the
// gateway (streaming, sentence chunking, VAD, barge-in) without API keys.

import type { ChatMessage, LiveEvents, LiveProvider, LiveSession, LLMProvider, STTProvider, TTSProvider } from './types.ts';
import { LIVE_SAMPLE_RATE } from './types.ts';
import { makeWav, pcmRms, tone } from '../audio.ts';

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export const mockSTT: STTProvider = {
  name: 'mock',
  async transcribe(audio, mimeType) {
    const kb = (audio.length / 1024).toFixed(1);
    return { text: `Mock transcript: I heard ${kb} kilobytes of ${mimeType.split(';')[0]}. What's a good 20 minute dinner?` };
  },
};

function mockAnswer(prompt: string): string {
  const p = prompt.toLowerCase();
  if (p.includes('dinner')) return 'Try garlic butter shrimp with rice. It takes about fifteen minutes and one pan. Want the steps?';
  if (p.includes('weather')) return "I'm the offline mock model, so no live weather. The real model would answer in one sentence.";
  if (p.includes('timer')) return 'Timers are a watch feature, so the real app hands that to Siri. Anything else?';
  return `You said: "${prompt.slice(0, 80)}". I'm the mock model, but the pipe works end to end. Add an API key for real answers.`;
}

export const mockLLM: LLMProvider = {
  name: 'mock',
  async *stream(messages: ChatMessage[], { signal }) {
    const last = [...messages].reverse().find((m) => m.role === 'user')?.content ?? '';
    const answer = mockAnswer(last);
    for (const word of answer.split(/(?<=\s)/)) {
      if (signal?.aborted) return;
      await sleep(25);
      yield word;
    }
    return { input_tokens: messages.reduce((n, m) => n + Math.ceil(m.content.length / 4), 0), output_tokens: Math.ceil(answer.length / 4) };
  },
};

export const mockTTS: TTSProvider = {
  name: 'mock',
  format: 'wav',
  async synthesize(text) {
    // A soft two-note chime whose length scales with the sentence length,
    // so playback timing in the client behaves like real speech.
    const words = text.split(/\s+/).filter(Boolean).length;
    const seconds = Math.min(4, 0.18 * words + 0.2);
    const sr = 16000;
    const a = tone(523.25, seconds / 2, sr, 0.18);
    const b = tone(659.25, seconds / 2, sr, 0.18);
    return makeWav(Buffer.concat([a, b]), sr);
  },
};

/** Echo bot: energy-based VAD, then plays the user's own speech back. */
export const mockLive: LiveProvider = {
  name: 'mock',
  connect({ vad }, ev: LiveEvents): LiveSession {
    let speaking = false;
    let silenceMs = 0;
    let captured: Buffer[] = [];
    let playing: NodeJS.Timeout | undefined;
    let closed = false;
    const threshold = 0.02;

    const respond = () => {
      const speech = Buffer.concat(captured);
      captured = [];
      const secs = speech.length / 2 / LIVE_SAMPLE_RATE;
      if (secs < 0.2) return;
      ev.onUserTranscript(`[mock] ${secs.toFixed(1)} seconds of speech`);
      const reply = `Echoing your ${secs.toFixed(1)} seconds back.`;
      for (const w of reply.split(/(?<=\s)/)) ev.onAssistantDelta(w);
      // Stream the echo back in 100 ms frames at real-time pace.
      const frame = (LIVE_SAMPLE_RATE / 10) * 2;
      let off = 0;
      playing = setInterval(() => {
        if (closed || off >= speech.length) {
          clearInterval(playing);
          playing = undefined;
          if (!closed) ev.onResponseDone(reply);
          return;
        }
        ev.onAudio(speech.subarray(off, off + frame));
        off += frame;
      }, 100);
    };

    queueMicrotask(() => ev.onReady());

    return {
      sendAudio(pcm) {
        if (closed) return;
        const loud = pcmRms(pcm) > threshold;
        const ms = (pcm.length / 2 / LIVE_SAMPLE_RATE) * 1000;
        if (loud && !speaking) {
          speaking = true;
          silenceMs = 0;
          if (playing) { clearInterval(playing); playing = undefined; }
          ev.onSpeechStarted();
        }
        if (speaking || vad === 'manual') captured.push(pcm);
        if (speaking && vad === 'server') {
          silenceMs = loud ? 0 : silenceMs + ms;
          if (silenceMs >= 600) {
            speaking = false;
            ev.onSpeechStopped();
            respond();
          }
        }
      },
      commit() {
        speaking = false;
        ev.onSpeechStopped();
        respond();
      },
      cancel() {
        if (playing) { clearInterval(playing); playing = undefined; }
      },
      close() {
        closed = true;
        if (playing) clearInterval(playing);
        ev.onClose();
      },
    };
  },
};
