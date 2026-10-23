// Runs the backend test suite on the Firestore driver (P1-06A). Started by
// `npm run test:firestore` inside `firebase emulators:exec`, which sets
// FIRESTORE_EMULATOR_HOST, so nothing here ever reaches a real project.
// Files (plans, map documents) go to a fresh temporary folder, never the
// server's own uploads/ or data/.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('FIRESTORE_EMULATOR_HOST is not set: run this through `npm run test:firestore`.');
  process.exit(1);
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'liqo-fs-test-'));
const env = { ...process.env, DB_DRIVER: 'firestore', FILES_ROOT: root, FIREBASE_PROJECT_ID: 'demo-liqo' };
const args = ['--test', '--test-concurrency=1', ...process.argv.slice(2)];
const r = spawnSync(process.execPath, args, { stdio: 'inherit', env });
fs.rmSync(root, { recursive: true, force: true });
process.exit(r.status ?? 1);
