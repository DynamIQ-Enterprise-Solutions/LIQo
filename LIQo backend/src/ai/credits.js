// AI credits per mall admin (Round 19, owner decisions 2026-10-23): the pure
// rules, tested on their own. The SQL is in repos/credits.js.
//
// A balance is a share of the IQGateway wallet set aside for one mall admin.
// Giving credits moves no money: the wallet only goes down when a reading is
// paid. "Given" is what admins hold and have not used; "Free" is the rest.

/** Credits to four decimals (the column's precision). */
export const round4 = (n) => Math.round(Number(n) * 10000) / 10000;

/**
 * The superadmin's view of the wallet. [wallet] is the gateway balance (null
 * when it could not be read), [given] the sum of the admins' positive balances.
 */
export function walletSplit({ wallet, given, used = 0 }) {
  const g = round4(Math.max(0, given ?? 0));
  if (wallet == null) return { wallet: null, given: g, free: null, used: round4(used), overGiven: null };
  const w = round4(wallet);
  return { wallet: w, given: g, free: round4(Math.max(0, w - g)), used: round4(used), overGiven: g > w ? round4(g - w) : 0 };
}

/**
 * Why giving [amount] to an admin holding [balance] is refused, or null when
 * it is allowed: the cap, the wallet, and no giving while over-given.
 */
export function refuseGive({ amount, balance, cap, wallet, given }) {
  if (!(amount > 0)) return 'Give more than 0 credits.';
  if (wallet == null) return 'The AI wallet could not be checked, so no credits can be given right now. Try again in a moment.';
  if (given > wallet) {
    return `Admins already hold ${round4(given - wallet)} more credits than the wallet has. Top up the IQGateway wallet before giving more.`;
  }
  const room = round4(cap - Math.max(0, balance));
  if (amount > room + 1e-9) {
    return room <= 0 ? `This admin already has the most allowed (${cap} credits).` : `That would pass the most allowed per admin (${cap}). At most ${room} more can be given.`;
  }
  const free = round4(wallet - given);
  if (amount > free + 1e-9) return free <= 0 ? 'No credits are free to give. Top up the wallet or take credits back from an admin.' : `Only ${free} credits are free to give.`;
  return null;
}

/** Why taking [amount] back from an admin holding [balance] is refused, or null. */
export function refuseRemove({ amount, balance }) {
  if (!(amount > 0)) return 'Take back more than 0 credits.';
  if (balance <= 0) return 'This admin has no credits to take back.';
  if (amount > round4(balance) + 1e-9) return `This admin only has ${round4(balance)} credits.`;
  return null;
}

/**
 * What a new (or reactivated) mall admin starts with: the starting credits,
 * as far as the wallet has free credits and the cap allows; with a note for
 * the person who created the account when it is less.
 */
export function startCredits({ start, cap, wallet, given }) {
  if (!(start > 0)) return { amount: 0, note: null };
  if (wallet == null) return { amount: 0, note: 'The AI wallet could not be checked, so this admin starts with 0 credits. Give credits in Analytics later.' };
  const free = given > wallet ? 0 : round4(wallet - given);
  const amount = round4(Math.max(0, Math.min(start, cap, free)));
  if (amount >= start) return { amount, note: null };
  return {
    amount,
    note: amount <= 0 ? 'No AI credits were free, so this admin starts with 0. Give credits in Analytics once the wallet has room.' : `Started with ${amount} AI credits; the wallet had no more free.`,
  };
}
