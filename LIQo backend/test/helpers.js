// Test helpers: start the real app on a random port against the local DB (SQL Server or the Firestore emulator),
// create throw-away records with a unique suffix, and clean them up after.
process.env.RATE_LIMIT = 'off';

import { createApp } from '../src/app.js';
import * as db from './support/testDb.js';
import * as users from '../src/repos/users.js';
import { hashPassword } from '../src/utils/password.js';
import * as credits from '../src/repos/credits.js';

export const PASSWORD = 'TestPass123';

export async function startServer() {
  await db.prepare();
  const app = createApp();
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}/api`;
  return { server, base };
}

export async function stopServer(server) {
  await new Promise((resolve) => server.close(resolve));
  await db.close();
}

export function api(base) {
  return async (method, path, { token, body } = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = text;
    }
    return { status: res.status, body: json };
  };
}

/** Creates a fixture set with a unique tag so tests never collide with real data. */
export async function makeFixtures(tag) {
  const mk = async (role, { mustChange = false, prefix = role } = {}) =>
    users.create({
      email: `${prefix}.${tag}@test.local`,
      fullName: `${prefix} ${tag}`,
      role,
      passwordHash: await hashPassword(PASSWORD),
      mustChange,
    });

  const superadminId = await mk('superadmin');
  const supervisorId = await mk('supervisor');
  const mallAdminId = await mk('mall_admin');
  const ownerId = await mk('store_owner');
  const tempUserId = await mk('supervisor', { mustChange: true, prefix: 'temp' });

  const mallA = await db.insertMall(`Mall A ${tag}`);
  const mallB = await db.insertMall(`Mall B ${tag}`);
  const branchA = await db.insertBranch(mallA, `Branch A ${tag}`);
  const branchB = await db.insertBranch(mallB, `Branch B ${tag}`);

  await db.assignOwnerMall(supervisorId, mallA);
  await db.assignAdminBranch(mallAdminId, branchA);
  // The fixture admin reports to the fixture owner (Round 4).
  await db.setUser(mallAdminId, { reports_to: supervisorId });
  const storeA = await db.insertStore(branchA, `Store A ${tag}`);
  await db.assignStoreOwner(ownerId, storeA);

  return { superadminId, supervisorId, mallAdminId, ownerId, tempUserId, mallA, mallB, branchA, branchB, storeA };
}

/**
 * Gives a fixture mall admin AI credits directly (no wallet or cap check), so
 * tests about reading plans can read (Round 19: a mall admin needs credits).
 */
export async function giveTestCredits(userId, amount) {
  return credits.withCreditsLock((tx) => credits.change(tx, { userId, delta: amount, kind: 'grant', note: 'test setup' }));
}

export async function cleanFixtures(tag) {
  await db.cleanTagged(tag);
}
