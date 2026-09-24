import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import { config } from './config.ts';
import { bearer, readBody, sendJson } from './http.ts';
import { handleLive } from './live.ts';
import { loadProviders, type Providers } from './providers/index.ts';
import { applyEntitlement, authenticate, getConversation, getUsage, limitsFor, registerDevice } from './store.ts';
import { handleTurn } from './turn.ts';

const PUBLIC = fileURLToPath(new URL('../public/', import.meta.url));
const MIME: Record<string, string> = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' };

export function createApp(providers: Providers = loadProviders()) {
  const route = async (req: IncomingMessage, res: ServerResponse) => {
    const url = new URL(req.url ?? '/', 'http://x');
    const path = url.pathname;

    if (req.method === 'GET' && path === '/healthz') {
      return sendJson(res, 200, { ok: true, providers: Object.fromEntries(Object.entries(providers).map(([k, v]) => [k, v.name])) });
    }

    if (req.method === 'POST' && path === '/v1/devices') {
      const body = await readBody(req, 4096).catch(() => Buffer.alloc(0));
      let meta = {};
      try { meta = body.length ? JSON.parse(body.toString()) : {}; } catch { /* optional */ }
      const { device, token } = registerDevice(meta);
      return sendJson(res, 201, { device_id: device.id, token, plan: device.plan, limits: limitsFor(device) });
    }

    if (path.startsWith('/v1/')) {
      const device = authenticate(bearer(req));
      if (!device) return sendJson(res, 401, { code: 'unauthorized', message: 'Missing or invalid token.' });

      if (req.method === 'GET' && path === '/v1/me') {
        return sendJson(res, 200, { device_id: device.id, plan: device.plan, limits: limitsFor(device), usage: getUsage(device) });
      }
      if (req.method === 'POST' && path === '/v1/turns') return handleTurn(req, res, device, providers, url);
      if (req.method === 'POST' && path === '/v1/entitlements/apple') {
        // Prototype stub: accepts {original_transaction_id}. See store.ts for the production checklist.
        const j = JSON.parse((await readBody(req, 16384)).toString() || '{}');
        if (!j.original_transaction_id && !j.signed_transaction) return sendJson(res, 400, { code: 'bad_request', message: 'Missing transaction.' });
        applyEntitlement(device, String(j.original_transaction_id ?? 'stub'));
        return sendJson(res, 200, { plan: device.plan, limits: limitsFor(device) });
      }
      const conv = /^\/v1\/conversations\/([\w-]+)$/.exec(path);
      if (req.method === 'GET' && conv) {
        const c = getConversation(device.id, conv[1]);
        return sendJson(res, 200, { id: c.id, messages: c.messages.map((m) => ({ role: m.role, text: m.content, at: m.at })) });
      }
      return sendJson(res, 404, { code: 'not_found', message: path });
    }

    // Static: the browser watch simulator (dev only).
    if (req.method === 'GET') {
      const rel = normalize(path === '/' ? 'index.html' : path.slice(1));
      if (rel.startsWith('..')) return sendJson(res, 400, { code: 'bad_path' });
      try {
        const data = await readFile(join(PUBLIC, rel));
        res.writeHead(200, { 'Content-Type': MIME[extname(rel)] ?? 'application/octet-stream' });
        return res.end(data);
      } catch { /* fallthrough */ }
    }
    sendJson(res, 404, { code: 'not_found', message: path });
  };

  const server = createServer((req, res) => {
    route(req, res).catch((err) => {
      console.error(err);
      if (!res.headersSent) sendJson(res, 500, { code: 'internal', message: 'Internal error.' });
      else res.end();
    });
  });

  const wss = new WebSocketServer({ noServer: true, maxPayload: 256 * 1024 });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url ?? '/', 'http://x');
    if (url.pathname !== '/v1/live') return socket.destroy();
    const device = authenticate(url.searchParams.get('token') ?? bearer(req));
    wss.handleUpgrade(req, socket, head, (ws) => {
      if (!device) return ws.close(4001, 'unauthorized');
      handleLive(ws, device, providers);
    });
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = createApp();
  server.listen(config.port, config.host, () => {
    console.log(`WatchGPT gateway on http://localhost:${config.port}  providers=${JSON.stringify(config.providers)}`);
    if (config.tokenSecret === 'dev-insecure-secret') console.warn('⚠ TOKEN_SECRET not set (fine for dev, never for prod)');
  });
}
