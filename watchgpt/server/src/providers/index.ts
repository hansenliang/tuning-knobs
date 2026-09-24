import { config } from '../config.ts';
import { mockLive, mockLLM, mockSTT, mockTTS } from './mock.ts';
import { openaiLive, openaiSTT, openaiTTS, openrouterLLM } from './real.ts';
import { anthropicLLM } from './anthropic.ts';
import type { LiveProvider, LLMProvider, STTProvider, TTSProvider } from './types.ts';

export interface Providers {
  stt: STTProvider;
  llm: LLMProvider;
  tts: TTSProvider;
  live: LiveProvider;
}

const table = {
  stt: { mock: mockSTT, openai: openaiSTT },
  llm: { mock: mockLLM, anthropic: anthropicLLM, openrouter: openrouterLLM },
  tts: { mock: mockTTS, openai: openaiTTS },
  live: { mock: mockLive, openai: openaiLive },
} as const;

function choose<K extends keyof typeof table>(leg: K): Providers[K] {
  const name = config.providers[leg];
  const p = (table[leg] as unknown as Record<string, Providers[K]>)[name];
  if (!p) throw new Error(`Unknown ${leg} provider "${name}". Options: ${Object.keys(table[leg]).join(', ')}`);
  return p;
}

export function loadProviders(): Providers {
  return { stt: choose('stt'), llm: choose('llm'), tts: choose('tts'), live: choose('live') };
}
