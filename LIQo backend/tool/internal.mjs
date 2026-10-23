// The internal deployment (owner decisions 2026-10-23, docs/internal-deploy.md):
// the web app on Firebase Hosting, the API on this PC on Firestore, reached
// through a Cloudflare quick tunnel until a domain gives it a fixed address.
//
//   npm run serve:internal          start the API (Firestore, port 3100) and the tunnel;
//                                   when the tunnel's address changed, rebuild and
//                                   redeploy the web app so it points at it
//   npm run deploy:internal         rebuild and redeploy the web app (same address)
//   npm run deploy:internal -- --rules   also deploy the Firestore rules and indexes
//   npm run seed:internal           create the first superadmin on Firestore
//
// No secrets live here: the key file's path and the project come from .env.
import 'dotenv/config';
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const BACKEND = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ROOT = path.resolve(BACKEND, '..');
const WEB = path.join(ROOT, 'LIQo web');
const STATE = path.join(BACKEND, 'data', 'internal-deploy.json');
const FIREBASE_CLI = path.join(BACKEND, 'node_modules', 'firebase-tools', 'lib', 'bin', 'firebase.js');

const PROJECT = process.env.FIREBASE_PROJECT_ID;
const PORT = Number(process.env.INTERNAL_PORT) || 3100;
const WEB_ORIGINS = PROJECT ? [`https://${PROJECT}.web.app`, `https://${PROJECT}.firebaseapp.com`] : [];

function fail(message) {
  console.error(`\n${message}\n`);
  process.exit(1);
}

function checkSetup() {
  if (!PROJECT) fail('FIREBASE_PROJECT_ID is missing from LIQo backend/.env.');
  const key = process.env.FIREBASE_KEY_FILE;
  if (!key || !fs.existsSync(key)) fail('FIREBASE_KEY_FILE in LIQo backend/.env must point to the service-account key file.');
  if (!fs.existsSync(FIREBASE_CLI)) fail('The Firebase tools are missing: run `npm install` in LIQo backend.');
}

const readState = () => {
  try {
    return JSON.parse(fs.readFileSync(STATE, 'utf8'));
  } catch {
    return {};
  }
};
const writeState = (s) => {
  fs.mkdirSync(path.dirname(STATE), { recursive: true });
  fs.writeFileSync(STATE, JSON.stringify(s, null, 2));
};

/** Runs a command to the end with its output shown; stops everything when it fails. */
function run(label, command, args, options = {}) {
  console.log(`\n> ${label}`);
  const r = spawnSync(command, args, { stdio: 'inherit', ...options });
  if (r.status !== 0) fail(`${label} failed (exit ${r.status ?? r.error?.message}).`);
}

const firebase = (label, args) => run(label, process.execPath, [FIREBASE_CLI, ...args, '--project', PROJECT, '--non-interactive'], { cwd: ROOT });

export function deployRules() {
  firebase('Deploying the Firestore rules and indexes', ['deploy', '--only', 'firestore:rules,firestore:indexes']);
}

/** Builds the web app against [apiBase] and puts it on Firebase Hosting. */
export function deployWeb(apiBase) {
  // flutter is a .bat on Windows, so it runs through the shell; the arguments are fixed or a checked https URL.
  if (!/^https:\/\/[a-z0-9.-]+$/i.test(apiBase)) fail(`Refusing an unexpected API address: ${apiBase}`);
  run('Building the web app', 'flutter', ['build', 'web', '--release', `--dart-define=API_BASE=${apiBase}`], { cwd: WEB, shell: true });
  firebase('Deploying the web app to Firebase Hosting', ['deploy', '--only', 'hosting']);
  writeState({ ...readState(), apiBase, deployedAt: new Date().toISOString() });
  console.log(`\nThe web app at ${WEB_ORIGINS[0]} now talks to ${apiBase}`);
}

function portFree(port) {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.once('error', () => resolve(false));
    s.once('listening', () => s.close(() => resolve(true)));
    s.listen(port, '127.0.0.1');
  });
}

function cloudflaredPath() {
  if (process.env.CLOUDFLARED) return process.env.CLOUDFLARED;
  for (const p of ['C:/Program Files (x86)/cloudflared/cloudflared.exe', 'C:/Program Files/cloudflared/cloudflared.exe']) if (fs.existsSync(p)) return p;
  return 'cloudflared';
}

/** Starts a child, prefixes its lines, and resolves with the first match of [pattern] in its output. */
function startChild(label, command, args, options, pattern, timeoutMs) {
  const child = spawn(command, args, options);
  const found = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label} did not start within ${timeoutMs / 1000} s.`)), timeoutMs);
    const onData = (buf) => {
      for (const line of buf.toString().split(/\r?\n/)) {
        if (!line.trim()) continue;
        console.log(`[${label}] ${line}`);
        const m = line.match(pattern);
        if (m) {
          clearTimeout(timer);
          resolve(m[0]);
        }
      }
    };
    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    child.once('exit', (code) => reject(new Error(`${label} stopped (exit ${code}).`)));
  });
  return { child, found };
}

async function reachable(url, timeoutMs) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    try {
      const r = await fetch(`${url}/api/health`);
      if (r.ok) return true;
    } catch {
      // The new address can take a few seconds to resolve.
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  return false;
}

async function serve({ redeploy }) {
  checkSetup();
  // One API process per Firestore database (Blueprint trap 14).
  if (!(await portFree(PORT))) fail(`Port ${PORT} is in use: the internal API is probably already running in another window. Stop it first.`);

  const env = { ...process.env, DB_DRIVER: 'firestore', PORT: String(PORT), CORS_ORIGINS: WEB_ORIGINS.join(',') };
  delete env.FIRESTORE_EMULATOR_HOST;
  const api = startChild('api', process.execPath, ['src/server.js'], { cwd: BACKEND, env }, /listening on \d+/, 60_000);
  const children = [api.child];
  const stopAll = (code) => {
    for (const c of children) if (c.exitCode == null) c.kill();
    process.exit(code);
  };
  process.on('SIGINT', () => stopAll(0));
  try {
    await api.found;
    const tunnel = startChild('tunnel', cloudflaredPath(), ['tunnel', '--no-autoupdate', '--url', `http://localhost:${PORT}`], {}, /https:\/\/[a-z0-9-]+\.trycloudflare\.com/, 90_000);
    children.push(tunnel.child);
    const address = await tunnel.found;
    for (const c of children) c.once('exit', () => fail2(c === api.child ? 'The API stopped.' : 'The tunnel stopped.'));
    if (!(await reachable(address, 90_000))) throw new Error(`The tunnel address ${address} does not answer.`);
    console.log(`\nThe API answers at ${address}`);
    if (redeploy || readState().apiBase !== address) deployWeb(address);
    else console.log(`The web app already points at ${address}.`);
    console.log(`\nLIQo is live at ${WEB_ORIGINS[0]}. Keep this window open; Ctrl+C stops the API and the tunnel.\n`);
  } catch (err) {
    console.error(`\n${err.message}`);
    stopAll(1);
  }
  function fail2(message) {
    console.error(`\n${message} Stopping everything; start again with npm run serve:internal.`);
    stopAll(1);
  }
}

function seed() {
  checkSetup();
  const env = { ...process.env, DB_DRIVER: 'firestore' };
  delete env.FIRESTORE_EMULATOR_HOST;
  run('Creating the first superadmin on Firestore', process.execPath, ['src/db/seed.js', '--must-change'], { cwd: BACKEND, env });
}

const [command, ...flags] = process.argv.slice(2);
if (command === 'serve') await serve({ redeploy: flags.includes('--redeploy') });
else if (command === 'deploy') {
  checkSetup();
  if (flags.includes('--rules')) deployRules();
  const { apiBase } = readState();
  if (!apiBase) fail('No API address yet: start the API with `npm run serve:internal` first.');
  deployWeb(apiBase);
} else if (command === 'seed') seed();
else fail('Use: node tool/internal.mjs serve [--redeploy] | deploy [--rules] | seed');
