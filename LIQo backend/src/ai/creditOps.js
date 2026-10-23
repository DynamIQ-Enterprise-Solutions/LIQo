// AI credit operations used by several routes (Round 19): giving, starting
// credits, returning credits, and the checks around a reading.
import { AppError } from '../middleware/errors.js';
import * as settings from '../repos/settings.js';
import * as credits from '../repos/credits.js';
import * as gateway from './gateway.js';
import { refuseGive, refuseRemove, startCredits, round4 } from './credits.js';

/** The gateway wallet balance, or null when it cannot be read (no key, gateway down). */
export async function readWallet() {
  if (!gateway.aiConfigured()) return null;
  try {
    const q = await gateway.quota();
    return q.balance == null ? null : Number(q.balance);
  } catch {
    return null;
  }
}

/**
 * Gives [amount] credits to a mall admin (kind 'grant', or 'request' when it
 * approves [requestId]), after the cap and wallet checks. Returns the balance after.
 */
export async function give({ userId, amount, actorId, kind = 'grant', note = null, requestId = null, beforeChange = null }) {
  const wallet = await readWallet();
  const cap = await settings.getNumber('ai_credit_cap');
  return credits.withCreditsLock(async (tx) => {
    if (!(await credits.isActiveMallAdmin(userId, tx))) throw new AppError(400, 'Only active mall admins hold AI credits.');
    const { balance } = await credits.balanceOf(userId, tx);
    const given = await credits.givenTotal(tx);
    const why = refuseGive({ amount, balance, cap, wallet, given });
    if (why) throw new AppError(409, why);
    if (beforeChange) await beforeChange(tx);
    return credits.change(tx, { userId, delta: round4(amount), kind, actorId, note, requestId });
  });
}

/** Takes [amount] credits back from a mall admin (they return to the free part). */
export async function take({ userId, amount, actorId, note = null }) {
  return credits.withCreditsLock(async (tx) => {
    if (!(await credits.isActiveMallAdmin(userId, tx))) throw new AppError(400, 'Only active mall admins hold AI credits.');
    const { balance } = await credits.balanceOf(userId, tx);
    const why = refuseRemove({ amount, balance });
    if (why) throw new AppError(409, why);
    return credits.change(tx, { userId, delta: -round4(amount), kind: 'remove', actorId, note });
  });
}

/**
 * The starting credits for a new or reactivated mall admin: the setting, as far
 * as the wallet has free credits and the cap allows. Never refuses; returns
 * { amount, note } for the person who created the account.
 */
export async function grantStartCredits(userId, actorId) {
  const start = await settings.getNumber('ai_start_credits');
  if (!(start > 0)) return { amount: 0, note: null };
  const wallet = await readWallet();
  const cap = await settings.getNumber('ai_credit_cap');
  return credits.withCreditsLock(async (tx) => {
    const { balance } = await credits.balanceOf(userId, tx);
    const given = await credits.givenTotal(tx);
    const out = startCredits({ start, cap: Math.max(0, cap - Math.max(0, balance)), wallet, given });
    if (out.amount > 0) await credits.change(tx, { userId, delta: out.amount, kind: 'start', actorId });
    return out;
  });
}

/** A deactivated admin's credits go back to the free part, and their open request closes. */
export async function returnCredits(userId, actorId) {
  return credits.withCreditsLock(async (tx) => {
    const { balance } = await credits.balanceOf(userId, tx);
    const cancelled = await credits.cancelOpenRequest(userId, tx);
    let returned = 0;
    if (balance !== 0) {
      await credits.change(tx, { userId, delta: -balance, kind: 'returned', actorId });
      returned = balance;
    }
    return { returned, cancelledRequest: cancelled?.id ?? null };
  });
}

/**
 * May this person start a reading? A mall admin needs a balance above 0; a
 * superadmin reads from the free part of the wallet. Throws a plain refusal.
 */
export async function assertCanRead(user) {
  if (user.role === 'mall_admin') {
    const { balance } = await credits.balanceOf(user.id);
    if (balance <= 0) throw new AppError(409, 'You have no AI credits left. Ask a superadmin for more (Request credits).');
    return;
  }
  if (user.role === 'superadmin') {
    const wallet = await readWallet();
    if (wallet == null) return; // the gateway itself will say what is wrong
    const given = await credits.givenTotal();
    if (wallet - given <= 0) throw new AppError(409, 'All wallet credits are given to mall admins. Take some back in Analytics, or top up the wallet, to read as a superadmin.');
  }
}

/** Takes a paid reading's cost from the mall admin who ran it (it may end a little below 0). */
export async function chargeReading(user, cost, conversionId) {
  if (user.role !== 'mall_admin' || !(cost > 0)) return null;
  return credits.withCreditsLock((tx) => credits.change(tx, { userId: user.id, delta: -round4(cost), kind: 'reading', actorId: user.id, conversionId }));
}
