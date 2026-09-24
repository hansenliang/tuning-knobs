// GET /v1/live (WebSocket): hands-free full-duplex voice.
// The gateway relays PCM16 between the watch and a realtime speech-to-speech
// provider, meters seconds, enforces quota, and normalizes events (docs/API.md §3).
//
// Sessions outlive sockets. watchOS revokes the audio-session network grant
// (~36 s, FB24377808) and cellular handoffs drop connections, so an unexpected
// close only *detaches* the socket: upstream stays open for resumeWindowSeconds,
// output is buffered, and a reconnect with resume_session_id re-attaches.

import { randomBytes } from 'node:crypto';
import type { WebSocket } from 'ws';
import { config, SYSTEM_PROMPT } from './config.ts';
import type { Providers } from './providers/index.ts';
import { LIVE_SAMPLE_RATE, type LiveSession } from './providers/types.ts';
import { appendMessage, getConversation, liveSecondsLeft, recordLive, type Device } from './store.ts';

const MAX_BUFFERED_AUDIO_BYTES = 10 * LIVE_SAMPLE_RATE * 2; // 10 s

interface Session {
  id: string;
  device: Device;
  convId: string;
  upstream: LiveSession;
  allowance: number;
  startedAt: number;
  billed: number;
  meter?: NodeJS.Timeout;
  grace?: NodeJS.Timeout;
  ws?: WebSocket;
  backlog: (Buffer | string)[];
  backlogAudio: number;
  ready: boolean;
  ended: boolean;
}

const sessions = new Map<string, Session>();

function emit(s: Session, frame: object | Buffer) {
  const isAudio = Buffer.isBuffer(frame);
  const data = isAudio ? frame : JSON.stringify(frame);
  if (s.ready && s.ws && s.ws.readyState === s.ws.OPEN) {
    s.ws.send(data, { binary: isAudio });
    return;
  }
  if (s.ended) return;
  if (isAudio) {
    if (s.backlogAudio + frame.length > MAX_BUFFERED_AUDIO_BYTES) return; // drop the tail; captions still arrive
    s.backlogAudio += frame.length;
  } else if ((frame as { type?: string }).type === 'usage') {
    return; // stale meter readings are noise after a resume
  }
  s.backlog.push(data);
}

// Bill wall-clock session time (what realtime providers effectively charge for).
function bill(s: Session): number {
  const elapsed = (Date.now() - s.startedAt) / 1000;
  recordLive(s.device, elapsed - s.billed);
  s.billed = elapsed;
  return elapsed;
}

function end(s: Session, code?: number, reason?: string) {
  if (s.ended) return;
  s.ended = true;
  sessions.delete(s.id);
  clearInterval(s.meter);
  clearTimeout(s.grace);
  bill(s);
  s.upstream.close();
  if (code && s.ws && s.ws.readyState === s.ws.OPEN) s.ws.close(code, reason);
}

function attach(s: Session, ws: WebSocket, resumed: boolean) {
  clearTimeout(s.grace);
  s.grace = undefined;
  s.ws = ws;
  ws.send(JSON.stringify({
    type: 'session.ready', session_id: s.id, conversation_id: s.convId, sample_rate: LIVE_SAMPLE_RATE,
    max_seconds: Math.floor(s.allowance - s.billed), resume_window_s: config.resumeWindowSeconds, resumed,
  }));
  const backlog = s.backlog.splice(0);
  s.backlogAudio = 0;
  for (const f of backlog) ws.send(f, { binary: Buffer.isBuffer(f) });
}

function detach(s: Session, ws: WebSocket) {
  if (s.ws !== ws || s.ended) return;
  s.ws = undefined;
  s.grace = setTimeout(() => end(s), config.resumeWindowSeconds * 1000).unref();
}

function create(device: Device, p: Providers, msg: any, allowance: number): Session {
  const conv = getConversation(device.id, msg.conversation_id);
  const s = {
    id: `ls_${randomBytes(9).toString('base64url')}`,
    device, convId: conv.id, allowance, startedAt: Date.now(), billed: 0,
    backlog: [], backlogAudio: 0, ready: false, ended: false,
  } as unknown as Session;
  s.upstream = p.live.connect(
    { instructions: SYSTEM_PROMPT, voice: msg.voice ?? config.liveVoice, vad: msg.vad === 'manual' ? 'manual' : 'server', history: conv.messages },
    {
      onReady: () => {
        // session.ready must be the first frame the client sees, so attach only now.
        s.ready = true;
        if (s.ws) attach(s, s.ws, false);
      },
      onAudio: (pcm) => emit(s, pcm),
      onSpeechStarted: () => emit(s, { type: 'speech.started' }),
      onSpeechStopped: () => emit(s, { type: 'speech.stopped' }),
      onUserTranscript: (text) => {
        appendMessage(device.id, s.convId, 'user', text);
        emit(s, { type: 'transcript.user', text });
      },
      onAssistantDelta: (text) => emit(s, { type: 'transcript.assistant.delta', text }),
      onResponseDone: (text) => {
        appendMessage(device.id, s.convId, 'assistant', text);
        emit(s, { type: 'response.done', text });
      },
      onError: (code, message) => {
        emit(s, { type: 'error', code, message });
        end(s, 4500, 'upstream_failure');
      },
      onClose: () => end(s, 4500, 'upstream_closed'),
    },
  );
  s.meter = setInterval(() => {
    const elapsed = bill(s);
    emit(s, { type: 'usage', live_seconds: Math.round(elapsed) });
    if (elapsed >= s.allowance) {
      const max = s.allowance >= config.maxLiveSessionSeconds;
      emit(s, { type: 'error', code: max ? 'max_session_length' : 'quota_exceeded', message: 'Live time limit reached.' });
      end(s, max ? 4003 : 4002, 'limit');
    }
  }, 1000).unref();
  sessions.set(s.id, s);
  return s;
}

export function handleLive(ws: WebSocket, device: Device, p: Providers) {
  let s: Session | undefined;

  ws.on('message', (data, isBinary) => {
    if (isBinary) {
      if (s && s.ws === ws && !s.ended) s.upstream.sendAudio(data as Buffer);
      return;
    }
    let msg: any;
    try { msg = JSON.parse(data.toString()); } catch { return; }

    switch (msg.type) {
      case 'session.start': {
        if (s) return;
        const prior = msg.resume_session_id ? sessions.get(msg.resume_session_id) : undefined;
        if (prior && prior.device.id === device.id && !prior.ended) {
          if (prior.ws && prior.ws !== ws) prior.ws.terminate(); // half-open old socket
          s = prior;
          attach(s, ws, true);
          return;
        }
        const allowance = Math.min(liveSecondsLeft(device), config.maxLiveSessionSeconds);
        if (allowance <= 0) {
          ws.send(JSON.stringify({ type: 'error', code: 'quota_exceeded', message: 'No Live minutes left this month.' }));
          return ws.close(4002, 'quota_exceeded');
        }
        s = create(device, p, msg, allowance);
        s.ws = ws;
        if (s.ready) attach(s, ws, false);
        break;
      }
      case 'input.commit':
        s?.upstream.commit();
        break;
      case 'response.cancel':
        if (s) {
          s.upstream.cancel();
          s.backlog = s.backlog.filter((f) => !Buffer.isBuffer(f));
        }
        break;
      case 'session.end':
        if (s) end(s, 1000, 'bye');
        break;
    }
  });

  ws.on('close', () => s && detach(s, ws));
  ws.on('error', () => s && detach(s, ws));
}
