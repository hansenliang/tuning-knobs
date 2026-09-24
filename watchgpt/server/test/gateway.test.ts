// End-to-end tests against the real HTTP/WebSocket server with mock providers.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import WebSocket from 'ws';
import { createApp } from '../src/server.ts';
import { mockLive, mockLLM, mockSTT, mockTTS } from '../src/providers/mock.ts';
import { SentenceChunker } from '../src/sentences.ts';
import { makeWav, tone } from '../src/audio.ts';

const server = createApp({ stt: mockSTT, llm: mockLLM, tts: mockTTS, live: mockLive });
let base = '';
before(() => new Promise<void>((r) => server.listen(0, '127.0.0.1', () => {
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  r();
})));
after(() => { server.closeAllConnections(); server.close(); });

async function register() {
  const res = await fetch(`${base}/v1/devices`, { method: 'POST', body: '{"platform":"test"}' });
  assert.equal(res.status, 201);
  return (await res.json()) as { token: string; device_id: string };
}

async function ndjson(res: Response) {
  const text = await res.text();
  return text.trim().split('\n').map((l) => JSON.parse(l));
}

test('healthz reports providers', async () => {
  const j = await (await fetch(`${base}/healthz`)).json();
  assert.deepEqual(j.providers, { stt: 'mock', llm: 'mock', tts: 'mock', live: 'mock' });
});

test('rejects missing / forged tokens', async () => {
  assert.equal((await fetch(`${base}/v1/me`)).status, 401);
  const { token } = await register();
  const forged = token.slice(0, -2) + 'xx';
  assert.equal((await fetch(`${base}/v1/me`, { headers: { Authorization: `Bearer ${forged}` } })).status, 401);
  assert.equal((await fetch(`${base}/v1/me`, { headers: { Authorization: `Bearer ${token}` } })).status, 200);
});

test('text turn streams deltas, ordered audio segments, and completion', async () => {
  const { token } = await register();
  const res = await fetch(`${base}/v1/turns`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: "what's a good 20 minute dinner", reply: 'voice' }),
  });
  assert.equal(res.headers.get('content-type'), 'application/x-ndjson');
  const events = await ndjson(res);
  assert.equal(events[0].type, 'turn.started');
  assert.equal(events.at(-1).type, 'turn.completed');
  const deltas = events.filter((e) => e.type === 'text.delta').map((e) => e.text).join('');
  assert.equal(deltas, events.at(-1).text);
  const segs = events.filter((e) => e.type === 'audio.segment');
  assert.ok(segs.length >= 2, 'multiple sentence segments');
  assert.deepEqual(segs.map((s) => s.seq), segs.map((_, i) => i));
  assert.equal(Buffer.from(segs[0].data, 'base64').subarray(0, 4).toString(), 'RIFF');
  // Speech starts before the text finishes: first segment precedes the last delta.
  const firstSeg = events.findIndex((e) => e.type === 'audio.segment');
  const lastDelta = events.findLastIndex((e) => e.type === 'text.delta');
  assert.ok(firstSeg < lastDelta, 'first audio segment arrives before text is complete');
});

test('audio turn transcribes, reply=text skips TTS, history persists', async () => {
  const { token } = await register();
  const wav = makeWav(tone(440, 0.5, 16000), 16000);
  const res = await fetch(`${base}/v1/turns?reply=text&conversation_id=c_test1`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'audio/wav' },
    body: new Uint8Array(wav),
  });
  const events = await ndjson(res);
  assert.equal(events.find((e) => e.type === 'transcript')?.text.startsWith('Mock transcript'), true);
  assert.equal(events.some((e) => e.type === 'audio.segment'), false);
  const conv = await (await fetch(`${base}/v1/conversations/c_test1`, { headers: { Authorization: `Bearer ${token}` } })).json();
  assert.deepEqual(conv.messages.map((m: any) => m.role), ['user', 'assistant']);
});

test('conversations are isolated per device', async () => {
  const a = await register();
  const b = await register();
  await (await fetch(`${base}/v1/turns`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${a.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'secret', conversation_id: 'c_shared' }),
  })).text();
  const res = await fetch(`${base}/v1/turns`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${b.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'hi', conversation_id: 'c_shared' }),
  });
  const events = await ndjson(res);
  assert.notEqual(events[0].conversation_id, 'c_shared');
});

test('unsupported media and quota errors', async () => {
  const { token } = await register();
  const bad = await fetch(`${base}/v1/turns`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'text/plain' }, body: 'x' });
  assert.equal(bad.status, 415);
  await Promise.all(Array.from({ length: 30 }, async () => {
    await (await fetch(`${base}/v1/turns`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'hi', reply: 'text' }),
    })).text();
  }));
  const over = await fetch(`${base}/v1/turns`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'hi' }),
  });
  assert.equal(over.status, 402);
  assert.equal((await over.json()).code, 'quota_exceeded');
});

test('live: VAD, transcript, echoed audio, barge-in events', async () => {
  const { token } = await register();
  const ws = new WebSocket(`${base.replace('http', 'ws')}/v1/live?token=${token}`);
  const events: any[] = [];
  let audioBytes = 0;
  const done = new Promise<void>((resolve) => {
    ws.on('message', (data, isBinary) => {
      if (isBinary) { audioBytes += (data as Buffer).length; return; }
      const e = JSON.parse(data.toString());
      events.push(e);
      if (e.type === 'session.ready') {
        // 0.6 s of "speech" then 0.8 s of silence, in 100 ms frames.
        const speech = tone(300, 0.6, 24000, 0.3);
        const silence = Buffer.alloc(0.8 * 24000 * 2);
        const all = Buffer.concat([speech, silence]);
        for (let off = 0; off < all.length; off += 4800) ws.send(all.subarray(off, off + 4800));
      }
      if (e.type === 'response.done') resolve();
    });
  });
  await new Promise((r) => ws.on('open', r));
  ws.send(JSON.stringify({ type: 'session.start' }));
  await done;
  const types = events.map((e) => e.type);
  for (const t of ['session.ready', 'speech.started', 'speech.stopped', 'transcript.user', 'transcript.assistant.delta', 'response.done']) {
    assert.ok(types.includes(t), `saw ${t}`);
  }
  assert.ok(audioBytes > 0.5 * 24000 * 2, 'echoed audio back');
  ws.close();
});

test('live: dropped socket resumes the same session and flushes buffered output', async () => {
  const { token } = await register();
  const url = `${base.replace('http', 'ws')}/v1/live?token=${token}`;
  const first = new WebSocket(url);
  const ready: any = await new Promise((resolve) => {
    first.on('open', () => first.send(JSON.stringify({ type: 'session.start' })));
    first.on('message', (d, bin) => { if (!bin) { const e = JSON.parse(d.toString()); if (e.type === 'session.ready') resolve(e); } });
  });
  assert.equal(ready.resumed, false);
  assert.equal(ready.resume_window_s, 15);
  // Speak, then the watch loses its network grant mid-turn (hard drop, no session.end).
  const all = Buffer.concat([tone(300, 0.5, 24000, 0.3), Buffer.alloc(0.8 * 24000 * 2)]);
  for (let off = 0; off < all.length; off += 4800) first.send(all.subarray(off, off + 4800));
  await new Promise((r) => setTimeout(r, 50));
  first.terminate();
  await new Promise((r) => setTimeout(r, 900)); // server answers while detached

  const second = new WebSocket(url);
  const events: any[] = [];
  let audio = 0;
  await new Promise<void>((resolve) => {
    second.on('open', () => second.send(JSON.stringify({ type: 'session.start', resume_session_id: ready.session_id })));
    second.on('message', (d, bin) => {
      if (bin) { audio += (d as Buffer).length; return; }
      const e = JSON.parse(d.toString());
      events.push(e);
      if (e.type === 'response.done') resolve();
    });
  });
  assert.equal(events[0].type, 'session.ready');
  assert.equal(events[0].resumed, true);
  assert.equal(events[0].session_id, ready.session_id);
  assert.ok(audio > 0, 'buffered audio flushed');
  second.send(JSON.stringify({ type: 'session.end' }));
  const code = await new Promise((r) => second.on('close', (c) => r(c)));
  assert.equal(code, 1000);
});

test('live: resume with unknown id starts a fresh session', async () => {
  const { token } = await register();
  const ws = new WebSocket(`${base.replace('http', 'ws')}/v1/live?token=${token}`);
  const e: any = await new Promise((resolve) => {
    ws.on('open', () => ws.send(JSON.stringify({ type: 'session.start', resume_session_id: 'ls_nope' })));
    ws.on('message', (d, bin) => !bin && resolve(JSON.parse(d.toString())));
  });
  assert.equal(e.type, 'session.ready');
  assert.equal(e.resumed, false);
  ws.close();
});

test('live: rejects bad token with 4001', async () => {
  const ws = new WebSocket(`${base.replace('http', 'ws')}/v1/live?token=nope`);
  const code = await new Promise((r) => ws.on('close', (c) => r(c)));
  assert.equal(code, 4001);
});

test('sentence chunker: short first chunk, abbreviations, flush', () => {
  const c = new SentenceChunker();
  const out = [
    ...c.push('Sure. '),
    ...c.push('Use e.g. garlic and 3.5 cups of rice. Then '),
    ...c.push('simmer for ten minutes until soft. Done'),
    ...c.flush(),
  ];
  assert.deepEqual(out, ['Sure. Use e.g. garlic and 3.5 cups of rice.', 'Then simmer for ten minutes until soft.', 'Done']);
});
