// Runtime configuration. Every provider leg falls back to a deterministic mock
// when its API key is missing, so the whole stack runs offline for dev + tests.

export type Plan = 'trial' | 'pro';

export interface Limits {
  turns_per_day: number; // fair-use guard, not a selling point
  live_seconds_per_month: number; // the metered resource (realtime voice costs ~$0.02-0.03/min)
}

const env = process.env;
const pick = (name: string, key: string | undefined, real: string) =>
  (env[name] ?? (key ? real : 'mock')) as string;

export const config = {
  port: Number(env.PORT ?? 8787),
  host: env.HOST ?? '0.0.0.0',
  // HMAC secret for device tokens. MUST be set in production.
  tokenSecret: env.TOKEN_SECRET ?? 'dev-insecure-secret',

  anthropicKey: env.ANTHROPIC_API_KEY,
  openrouterKey: env.OPENROUTER_API_KEY,
  openaiKey: env.OPENAI_API_KEY,

  providers: {
    stt: pick('STT_PROVIDER', env.OPENAI_API_KEY, 'openai'),
    llm: env.LLM_PROVIDER ?? (env.ANTHROPIC_API_KEY ? 'anthropic' : env.OPENROUTER_API_KEY ? 'openrouter' : 'mock'),
    tts: pick('TTS_PROVIDER', env.OPENAI_API_KEY, 'openai'),
    live: pick('LIVE_PROVIDER', env.OPENAI_API_KEY, 'openai'),
  },

  // Product-level model aliases -> concrete model IDs, per LLM provider.
  // The watch only ever says "fast" or "smart", so swapping models is a server deploy.
  // OpenRouter IDs per research/03 (Sep 2026): verify at https://openrouter.ai/models.
  modelsByProvider: {
    anthropic: { fast: 'claude-haiku-4-5', smart: 'claude-sonnet-5' },
    openrouter: { fast: 'anthropic/claude-haiku-4.5', smart: 'anthropic/claude-sonnet-5' },
    mock: { fast: 'mock-fast', smart: 'mock-smart' },
  } as Record<string, Record<string, string>>,

  sttModel: env.STT_MODEL ?? 'gpt-4o-mini-transcribe',
  ttsModel: env.TTS_MODEL ?? 'gpt-4o-mini-tts',
  ttsVoice: env.TTS_VOICE ?? 'alloy',
  liveModel: env.LIVE_MODEL ?? 'gpt-realtime-2.1-mini',
  liveVoice: env.LIVE_VOICE ?? 'marin',

  maxAudioBytes: 2 * 1024 * 1024,
  maxLiveSessionSeconds: 15 * 60,
  resumeWindowSeconds: Number(env.RESUME_WINDOW_S ?? 15),
  historyMessages: 20,

  limits: {
    trial: { turns_per_day: 30, live_seconds_per_month: 5 * 60 },
    pro: { turns_per_day: 300, live_seconds_per_month: 60 * 60 },
  } as Record<Plan, Limits>,
};

export function modelFor(alias: string | undefined): string {
  const table = config.modelsByProvider[config.providers.llm] ?? config.modelsByProvider.mock;
  const key = alias === 'smart' ? 'smart' : 'fast';
  return (key === 'smart' ? env.MODEL_SMART : env.MODEL_FAST) ?? table[key];
}

export const SYSTEM_PROMPT = `You are WatchGPT, a voice assistant running on the user's Apple Watch.
Your replies are spoken aloud and shown on a tiny screen, so:
- Lead with the answer. Default to 1-3 short sentences (under ~60 words) unless the user asks for detail.
- Plain conversational text only: no markdown, bullet lists, tables, code blocks, URLs, or emoji.
- Say numbers, times and units the way a person would say them.
- If a request truly needs a long answer, give the short version and offer to continue.
- The user may be walking, driving or working out; be direct and warm, never chatty.`;
