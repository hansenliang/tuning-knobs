// POST /v1/turns: one push-to-talk (or typed) exchange, streamed as NDJSON.
//
//   audio/text in ──► STT ──► LLM (streaming) ──► sentence chunker ──► TTS (parallel)
//                                   │                                     │
//                                   └── text.delta events                 └── audio.segment events (in order)

import type { IncomingMessage, ServerResponse } from 'node:http';
import { randomBytes } from 'node:crypto';
import { config, modelFor, SYSTEM_PROMPT } from './config.ts';
import type { Providers } from './providers/index.ts';
import type { ChatMessage } from './providers/types.ts';
import { SentenceChunker } from './sentences.ts';
import { appendMessage, canTurn, getConversation, recordTurn, resetsAt, type Device } from './store.ts';
import { readBody, sendJson } from './http.ts';

const AUDIO_TYPES = /^audio\/(mp4|m4a|x-m4a|aac|wav|x-wav|webm|mpeg|ogg)$/;

export async function handleTurn(req: IncomingMessage, res: ServerResponse, device: Device, p: Providers, url: URL) {
  if (!canTurn(device)) {
    return sendJson(res, 402, { code: 'quota_exceeded', message: 'Daily turn limit reached.', resets_at: resetsAt() });
  }

  const ctype = (req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
  let body: Buffer;
  try {
    body = await readBody(req, config.maxAudioBytes);
  } catch {
    return sendJson(res, 413, { code: 'audio_too_large', message: `Max ${config.maxAudioBytes} bytes.` });
  }

  let text: string | undefined;
  let audio: Buffer | undefined;
  let params: Record<string, string | undefined> = Object.fromEntries(url.searchParams);
  if (ctype === 'application/json') {
    try {
      const j = JSON.parse(body.toString('utf8'));
      text = typeof j.text === 'string' ? j.text.trim() : undefined;
      params = { ...params, conversation_id: j.conversation_id, reply: j.reply, model: j.model };
    } catch {
      return sendJson(res, 400, { code: 'bad_request', message: 'Invalid JSON.' });
    }
    if (!text) return sendJson(res, 400, { code: 'bad_request', message: 'Missing "text".' });
  } else if (AUDIO_TYPES.test(ctype)) {
    if (body.length < 200) return sendJson(res, 400, { code: 'bad_request', message: 'Audio too short.' });
    audio = body;
  } else {
    return sendJson(res, 415, { code: 'unsupported_media_type', message: `Unsupported Content-Type "${ctype}".` });
  }

  const wantVoice = (params.reply ?? 'voice') !== 'text';
  const model = modelFor(params.model);
  const conv = getConversation(device.id, params.conversation_id);
  const turnId = `t_${randomBytes(6).toString('base64url')}`;

  res.writeHead(200, {
    'Content-Type': 'application/x-ndjson',
    'Cache-Control': 'no-store',
    'X-Accel-Buffering': 'no', // disable proxy buffering (nginx/Fly/Render)
  });
  const write = (evt: object) => !res.writableEnded && res.write(JSON.stringify(evt) + '\n');
  const abort = new AbortController();
  res.on('close', () => abort.abort());

  write({ type: 'turn.started', turn_id: turnId, conversation_id: conv.id });
  recordTurn(device);

  try {
    if (audio) {
      const t0 = Date.now();
      const { text: heard } = await p.stt.transcribe(audio, ctype);
      text = heard.trim();
      write({ type: 'transcript', text, ms: Date.now() - t0 });
      if (!text) {
        write({ type: 'error', code: 'no_speech', message: "Didn't catch that.", retryable: true });
        return res.end();
      }
    }

    const messages: ChatMessage[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      ...conv.messages.map(({ role, content }) => ({ role, content })),
      { role: 'user', content: text! },
    ];
    appendMessage(device.id, conv.id, 'user', text!);

    const chunker = new SentenceChunker();
    let seq = 0;
    let full = '';
    // Segments synthesize concurrently but are written strictly in order.
    let chain = Promise.resolve();
    const speak = (sentence: string) => {
      if (!wantVoice) return;
      const n = seq++;
      const pending = p.tts.synthesize(sentence, { signal: abort.signal }).then(
        (buf) => ({ ok: true as const, buf }),
        (err) => ({ ok: false as const, err }),
      );
      chain = chain.then(async () => {
        const r = await pending;
        if (r.ok) write({ type: 'audio.segment', seq: n, format: p.tts.format, text: sentence, data: r.buf.toString('base64') });
        else write({ type: 'audio.error', seq: n, message: String(r.err?.message ?? r.err) });
      });
    };

    const gen = p.llm.stream(messages, { model, signal: abort.signal });
    let usage;
    for (;;) {
      const { value, done } = await gen.next();
      if (done) { usage = value; break; }
      full += value;
      write({ type: 'text.delta', text: value });
      chunker.push(value).forEach(speak);
    }
    chunker.flush().forEach(speak);
    await chain;

    appendMessage(device.id, conv.id, 'assistant', full);
    write({ type: 'turn.completed', turn_id: turnId, text: full, usage: usage ?? null });
  } catch (err: any) {
    if (!abort.signal.aborted) {
      write({ type: 'error', code: err?.code ?? 'internal', message: String(err?.message ?? err), retryable: err?.retryable ?? true });
    }
  } finally {
    res.end();
  }
}
