export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

/** Speech-to-text for push-to-talk turns (whole utterance, not streaming). */
export interface STTProvider {
  name: string;
  transcribe(audio: Buffer, mimeType: string): Promise<{ text: string; seconds?: number }>;
}

export interface LLMUsage {
  input_tokens: number;
  output_tokens: number;
}

/** Streaming chat completion. Yields text deltas; returns usage when done. */
export interface LLMProvider {
  name: string;
  stream(messages: ChatMessage[], opts: { model: string; signal?: AbortSignal }): AsyncGenerator<string, LLMUsage | undefined>;
}

/** Text-to-speech for one sentence. Returns a complete, standalone audio file. */
export interface TTSProvider {
  name: string;
  format: 'mp3' | 'aac' | 'wav';
  synthesize(text: string, opts?: { signal?: AbortSignal }): Promise<Buffer>;
}

/**
 * Realtime speech-to-speech session (live mode). The gateway owns the client
 * socket; the provider owns the upstream connection and emits normalized events.
 */
export interface LiveEvents {
  onReady(): void;
  onAudio(pcm16: Buffer): void;
  onSpeechStarted(): void;
  onSpeechStopped(): void;
  onUserTranscript(text: string): void;
  onAssistantDelta(text: string): void;
  onResponseDone(text: string): void;
  onError(code: string, message: string): void;
  onClose(): void;
}

export interface LiveSession {
  sendAudio(pcm16: Buffer): void;
  commit(): void;
  cancel(): void;
  close(): void;
}

export interface LiveProvider {
  name: string;
  connect(opts: { instructions: string; voice: string; vad: 'server' | 'manual'; history: ChatMessage[] }, events: LiveEvents): LiveSession;
}

export const LIVE_SAMPLE_RATE = 24000;
