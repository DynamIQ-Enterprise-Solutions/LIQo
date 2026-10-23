// Firestore base for the firestore repo driver (P1-06A, owner decisions 2026-10-23).
//
// Conventions shared by every src/repos/firestore/*.js:
// - Collections are named like the SQL tables. Integer ids stay: nextId() hands
//   them out from a counter doc; a record's doc id is String(id) and it also
//   holds `id` as a number, so URLs and the apps never change.
// - What SQL Server enforced with constraints becomes guard docs written in the
//   same transaction (_unique/<kind>:<value>).
// - Aggregates are running totals (_totals, _daily) updated with the write, never
//   scans, to stay inside the Spark plan's daily reads and writes.
// - Big or immutable blobs live on disk (src/storage/files.js), never here.
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import fs from 'node:fs';

export { FieldValue, Timestamp };

let db;

/** The Firestore client: the emulator when FIRESTORE_EMULATOR_HOST is set, else the project from the key file. */
export function getDb() {
  if (db) return db;
  const projectId = process.env.FIREBASE_PROJECT_ID;
  let app = getApps()[0];
  if (!app) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      app = initializeApp({ projectId: projectId || 'liqo-local' });
    } else {
      const keyFile = process.env.FIREBASE_KEY_FILE;
      if (!keyFile || !fs.existsSync(keyFile)) throw new Error('Firestore is not set up: FIREBASE_KEY_FILE must point to the service-account key file.');
      const key = JSON.parse(fs.readFileSync(keyFile, 'utf8'));
      app = initializeApp({ credential: cert(key), projectId: projectId || key.project_id });
    }
  }
  db = getFirestore(app);
  db.settings({ ignoreUndefinedProperties: true });
  return db;
}

export const col = (name) => getDb().collection(name);
export const docOf = (name, id) => getDb().collection(name).doc(String(id));

/** Runs [fn] in a Firestore transaction (reads first, then writes, as Firestore requires). */
export function runTx(fn) {
  return getDb().runTransaction((tx) => fn(tx));
}

/** The next integer id for [collection]. Inside a transaction when [tx] is given. */
export async function nextId(collection, tx = null) {
  const ref = docOf('_counters', collection);
  if (tx) {
    const snap = await tx.get(ref);
    const next = (snap.exists ? snap.data().value : 0) + 1;
    tx.set(ref, { value: next });
    return next;
  }
  return runTx(async (t) => nextId(collection, t));
}

/** Converts Firestore Timestamps in a plain object to JS Dates (one level and arrays of objects). */
export function fromStore(data) {
  if (data == null) return null;
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    if (v instanceof Timestamp) out[k] = v.toDate();
    else out[k] = v;
  }
  return out;
}

/** All documents of a query as plain objects (dates as JS Dates). */
export async function all(queryOrRef) {
  const snap = await queryOrRef.get();
  return snap.docs.map((d) => fromStore(d.data()));
}

/** One document as a plain object, or null. */
export async function one(name, id, tx = null) {
  const ref = docOf(name, id);
  const snap = tx ? await tx.get(ref) : await ref.get();
  return snap.exists ? fromStore(snap.data()) : null;
}

/** A guard doc for a uniqueness rule (e.g. one email, one pending request). */
export const uniqueRef = (kind, value) => docOf('_unique', `${kind}:${String(value).toLowerCase()}`);

// ---- A small in-process cache for rarely changing collections (one server process) ----
const cache = new Map();

export async function cached(name, loader) {
  if (cache.has(name)) return cache.get(name);
  const value = await loader();
  cache.set(name, value);
  return value;
}

export function invalidate(...names) {
  if (names.length === 0) cache.clear();
  for (const n of names) cache.delete(n);
}

// ---- Running totals ----
export const dayKey = (d = new Date()) => {
  // Philippine time (UTC+8), matching how people read "today".
  const t = new Date(d.getTime() + 8 * 3600 * 1000);
  return t.toISOString().slice(0, 10);
};

/** Adds to counters on a running-total doc (e.g. _daily/2026-10-23 { login_success: +1 }). */
export function bump(tx, name, id, fields) {
  const inc = Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, FieldValue.increment(v)]));
  const ref = docOf(name, id);
  if (tx) tx.set(ref, inc, { merge: true });
  else return ref.set(inc, { merge: true });
  return null;
}

/** Test support: wipes every document (emulator only). */
export async function wipeEmulator() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('wipeEmulator() only runs against the emulator.');
  const cols = await getDb().listCollections();
  for (const c of cols) await getDb().recursiveDelete(c);
  invalidate();
}
