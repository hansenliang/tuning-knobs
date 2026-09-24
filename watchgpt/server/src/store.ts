// Accounts, usage metering, and conversation history.
// Prototype: in-memory. Production: Postgres (devices, entitlements, usage_daily)
// + Redis (conversation windows). Interfaces here are what those replace.

import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { config, type Limits, type Plan } from './config.ts';
import type { ChatMessage } from './providers/types.ts';

export interface Device {
  id: string;
  plan: Plan;
  createdAt: number;
  originalTransactionId?: string;
  meta: Record<string, unknown>;
}

interface Usage {
  day: string;
  month: string;
  turns: number;
  liveSeconds: number;
}

const devices = new Map<string, Device>();
const usage = new Map<string, Usage>();
const conversations = new Map<string, { deviceId: string; messages: (ChatMessage & { at: number })[] }>();

const sign = (id: string) => createHmac('sha256', config.tokenSecret).update(id).digest('base64url');
const today = () => new Date().toISOString().slice(0, 10);

export function registerDevice(meta: Record<string, unknown>): { device: Device; token: string } {
  const id = `dev_${randomBytes(9).toString('base64url')}`;
  const device: Device = { id, plan: 'trial', createdAt: Date.now(), meta };
  devices.set(id, device);
  return { device, token: `wgpt_${id}.${sign(id)}` };
}

export function authenticate(token: string | undefined | null): Device | undefined {
  if (!token) return;
  const m = /^wgpt_(dev_[\w-]+)\.([\w-]+)$/.exec(token.replace(/^Bearer\s+/i, ''));
  if (!m) return;
  const [, id, mac] = m;
  const expected = Buffer.from(sign(id));
  const got = Buffer.from(mac);
  if (expected.length !== got.length || !timingSafeEqual(expected, got)) return;
  return devices.get(id);
}

export function limitsFor(d: Device): Limits {
  return config.limits[d.plan];
}

function usageFor(d: Device): Usage {
  let u = usage.get(d.id);
  if (!u) {
    u = { day: today(), month: today().slice(0, 7), turns: 0, liveSeconds: 0 };
    usage.set(d.id, u);
  }
  if (u.day !== today()) { u.day = today(); u.turns = 0; }
  if (u.month !== today().slice(0, 7)) { u.month = today().slice(0, 7); u.liveSeconds = 0; }
  return u;
}

export function getUsage(d: Device) {
  const u = usageFor(d);
  return { turns_today: u.turns, live_seconds_this_month: Math.round(u.liveSeconds) };
}

export function resetsAt(): string {
  const t = new Date();
  t.setUTCHours(24, 0, 0, 0);
  return t.toISOString();
}

export const canTurn = (d: Device) => usageFor(d).turns < limitsFor(d).turns_per_day;
export const recordTurn = (d: Device) => void usageFor(d).turns++;
export const liveSecondsLeft = (d: Device) => Math.max(0, limitsFor(d).live_seconds_per_month - usageFor(d).liveSeconds);
export const recordLive = (d: Device, seconds: number) => void (usageFor(d).liveSeconds += seconds);

// StoreKit 2 binding (stub). Production: verify the JWS signature chain against
// Apple Root CA G3 (or use App Store Server Library), check bundleId/productId/
// expiresDate, then bind originalTransactionId -> device (and restore on reinstall).
export function applyEntitlement(d: Device, originalTransactionId: string) {
  d.originalTransactionId = originalTransactionId;
  d.plan = 'pro';
}

export function getConversation(deviceId: string, id: string | undefined) {
  const convId = id && /^[\w-]{1,64}$/.test(id) ? id : `c_${randomBytes(6).toString('base64url')}`;
  let c = conversations.get(convId);
  if (c && c.deviceId !== deviceId) {
    // Never leak another device's history; fork a fresh one.
    return getConversation(deviceId, undefined);
  }
  if (!c) {
    c = { deviceId, messages: [] };
    conversations.set(convId, c);
  }
  return { id: convId, messages: c.messages };
}

export function appendMessage(deviceId: string, convId: string, role: 'user' | 'assistant', text: string) {
  const c = conversations.get(convId);
  if (!c || c.deviceId !== deviceId || !text.trim()) return;
  c.messages.push({ role, content: text, at: Date.now() });
  if (c.messages.length > config.historyMessages) c.messages.splice(0, c.messages.length - config.historyMessages);
}
