// IQGateway client. The gateway speaks the OpenAI API (POST /chat/completions),
// so this is plain fetch, no SDK. Every call is server side; the key never
// leaves this process (not in responses, logs or audit details).

import { config } from '../config.js';
import { AppError } from '../middleware/errors.js';

const CHAT_TIMEOUT_MS = 4 * 60_000;
const HELPER_TIMEOUT_MS = 20_000;

export function aiConfigured() {
  return Boolean(config.ai.key);
}

function assertConfigured() {
  if (!aiConfigured()) throw new AppError(503, 'AI reading is not set up. A superadmin must add the IQGateway key on the server.');
}

/**
 * Turns a gateway answer that is not 2xx into a clear message for people.
 * Seen 2026-10-22: the gateway also answers 500 when the provider itself refuses
 * a request (Gemini: "Request contains an invalid argument."), not only when no
 * provider key is set up, so the gateway's own words decide which it was.
 */
function gatewayError(status, body) {
  const detail = (typeof body?.error === 'string' ? body.error : typeof body?.error?.message === 'string' ? body.error.message : '').slice(0, 300);
  const noProvider = /no .*(key|provider)|not configured|not enabled|disabled/i.test(detail);
  let err;
  switch (true) {
    case status === 401:
      err = new AppError(502, 'The AI service refused the platform key (missing, revoked or suspended). Ask a superadmin to check the AI setup.');
      break;
    case status === 402:
      err = new AppError(402, 'AI credits are used up: the wallet is empty or today\'s cap is reached. Try again tomorrow or ask for a top-up.');
      break;
    case status === 500 && noProvider:
      err = new AppError(502, 'The AI service has no provider set up for the chosen model. A superadmin can choose another model in Settings.');
      break;
    case status === 502 || status === 503 || status === 504:
      err = new AppError(502, 'The AI service failed or timed out. Try again in a moment.');
      break;
    default:
      // Plain words for people (owner, 2026-10-22: "graceful error handling");
      // the provider's own text goes to the server log only.
      err = new AppError(502, 'The chosen AI model could not take this reading, so nothing was added and no credits were used. Try again in a moment; if it keeps happening, a superadmin can choose another model in Settings.');
      // The provider rejected what we sent (not the key, not the wallet): the
      // reading may retry with a simpler answer format.
      err.requestRejected = status === 400 || status === 422 || status === 500;
  }
  return err;
}

async function call(method, path, body, timeoutMs) {
  assertConfigured();
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  let res;
  try {
    res = await fetch(`${config.ai.url}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${config.ai.key}`,
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: ctl.signal,
    });
  } catch (err) {
    if (err?.name === 'AbortError') throw new AppError(504, 'The AI service took too long to answer. Try a smaller part of the plan.');
    throw new AppError(502, 'The AI service could not be reached. Check the server\'s internet connection and try again.');
  } finally {
    clearTimeout(timer);
  }
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  if (!res.ok) {
    const err = gatewayError(res.status, json);
    // Every refusal goes to the server log (status and the gateway's own words,
    // never the key), so a failed reading can always be explained afterwards.
    const said = typeof json?.error === 'string' ? json.error : json?.error?.message ?? (json ? '' : text.slice(0, 200));
    console.error(`AI gateway ${method} ${path} → ${res.status}${said ? `: ${String(said).slice(0, 300)}` : ''}`.split(config.ai.key || '\u0000').join('[key]'));
    throw err;
  }
  if (json == null) throw new AppError(502, 'The AI service sent an answer that could not be read.');
  return json;
}

/**
 * The cost object the gateway adds to every answer, in plain numbers. Seen
 * 2026-10-22: {creditsCharged, costUSD, tenant, provider} (the docs said
 * credits/usd; both spellings are read).
 */
export function costOf(json) {
  const g = json?.x_gateway ?? {};
  const n = (v) => (v == null || v === '' ? null : Number.isFinite(Number(v)) ? Number(v) : null);
  return { credits: n(g.creditsCharged) ?? n(g.credits) ?? 0, usd: n(g.costUSD) ?? n(g.usd) ?? 0 };
}

/** The assistant text of a chat answer (string content or text parts). */
export function textOf(json) {
  const msg = json?.choices?.[0]?.message;
  const c = msg?.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) return c.map((p) => (typeof p === 'string' ? p : p?.text ?? '')).join('');
  return '';
}

/**
 * One chat completion. Returns the text, why it stopped, and what it cost.
 * `messages` are OpenAI-shaped (image parts as data: URLs).
 */
export async function chat({ model, messages, responseFormat, maxTokens = 16000, temperature = 0.1 }) {
  const json = await call(
    'POST',
    '/chat/completions',
    {
      model,
      messages,
      max_tokens: maxTokens,
      temperature,
      ...(responseFormat ? { response_format: responseFormat } : {}),
    },
    CHAT_TIMEOUT_MS,
  );
  return { text: textOf(json), finishReason: json?.choices?.[0]?.finish_reason ?? null, cost: costOf(json), model: json?.model ?? model };
}

/**
 * Every model the gateway lists. Its format (seen 2026-10-22) is OpenAI's list
 * with extras: {object:'list', data:[{id, owned_by, type: chat|image|audio|realtime, label, available}]}.
 */
export async function models() {
  const json = await call('GET', '/models', null, HELPER_TIMEOUT_MS);
  return normaliseModels(json);
}

export function normaliseModels(json) {
  const list = Array.isArray(json?.data) ? json.data : Array.isArray(json) ? json : [];
  const out = [];
  const seen = new Set();
  for (const e of list) {
    const id = typeof e === 'string' ? e : e?.id;
    if (typeof id !== 'string' || !id.trim() || seen.has(id.trim())) continue;
    seen.add(id.trim());
    out.push({
      id: id.trim(),
      label: typeof e?.label === 'string' && e.label.trim() ? e.label.trim() : id.trim(),
      provider: typeof e?.owned_by === 'string' ? e.owned_by : null,
      type: typeof e?.type === 'string' ? e.type : null,
      available: e?.available !== false,
    });
  }
  return out;
}

/**
 * The models that can read a plan: chat models the gateway marks available.
 * Image-making, audio and voice models cannot answer with a floor plan.
 */
export function readingModels(list) {
  return list.filter((m) => m.available && (m.type == null || m.type === 'chat')).map(({ id, label, provider }) => ({ id, label, provider }));
}

/**
 * The key's wallet. Format seen 2026-10-22:
 * {enforced, blocked, reason, balance, daily:{usedTokens, limitTokens, usedCredits, limitCredits}}.
 * A daily credit limit of 0 is reported as no cap (null).
 */
export async function quota() {
  const json = await call('GET', '/quota', null, HELPER_TIMEOUT_MS);
  return normaliseQuota(json);
}

/**
 * The credit bar's full mark (owner decision 2026-10-23: a full bar is the
 * wallet right after the last top-up). [prev] is what was remembered,
 * [balance] what the gateway reports now. A rise in the balance is a top-up and
 * makes the new balance the full mark; otherwise the mark never falls below the
 * balance. The first balance ever seen counts as full.
 */
export function walletMark(prev, balance) {
  if (balance == null || !Number.isFinite(balance)) return prev;
  const full = prev?.full;
  const last = prev?.last;
  if (full == null || last == null || balance > last + 1e-9) return { full: balance, last: balance };
  return { full: Math.max(full, balance), last: balance };
}

export function normaliseQuota(json) {
  const num = (v) => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
  const daily = json?.daily && typeof json.daily === 'object' ? json.daily : {};
  const cap = num(daily.limitCredits);
  return {
    balance: num(json?.balance),
    usedToday: num(daily.usedCredits),
    dailyCap: cap != null && cap > 0 ? cap : null,
    blocked: json?.blocked === true,
    reason: typeof json?.reason === 'string' && json.reason.trim() ? json.reason.trim().slice(0, 300) : null,
  };
}
