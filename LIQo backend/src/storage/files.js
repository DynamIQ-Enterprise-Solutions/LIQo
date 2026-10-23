// Every file the server keeps on its own disk (P1-06A, owner decisions
// 2026-10-23: during the internal test, files stay on the server PC under both
// database drivers; Firebase Storage would need the Blaze plan).
//
//   uploads/backdrops/<key>.png|jpg         a plan's picture
//   uploads/backdrops/<key>.dxf|dwg|svg      a drawing's original
//   uploads/backdrops/<key>.vector.json      a drawing's lines and texts
//   uploads/pictures/<key>.png|jpg          an announcement's picture (Round 21)
//   data/maps/<branch>/draft.json            a map draft          (Firestore driver)
//   data/maps/<branch>/versions/<n>.json     a published version  (Firestore driver; never rewritten)
//
// Nothing here is served statically; the routes decide who may read what.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = process.env.FILES_ROOT || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const PLANS = path.join(ROOT, 'uploads/backdrops');
/** Where plan files are kept (tests check them here; FILES_ROOT moves it). */
export const PLANS_DIR = PLANS;
const MAPS = path.join(ROOT, 'data/maps');
const PICTURES = path.join(ROOT, 'uploads/pictures');

fs.mkdirSync(PLANS, { recursive: true });
fs.mkdirSync(PICTURES, { recursive: true });

const pictureExt = (mime) => (mime === 'image/png' ? 'png' : 'jpg');

/** Floor plans and drawings. */
export const plans = {
  pictureName: (key, mime) => `${key}.${pictureExt(mime)}`,
  picturePath: (key, mime) => path.join(PLANS, `${key}.${pictureExt(mime)}`),
  hasPicture: (key, mime) => fs.existsSync(path.join(PLANS, `${key}.${pictureExt(mime)}`)),
  readPicture: (key, mime) => fs.readFileSync(path.join(PLANS, `${key}.${pictureExt(mime)}`)),
  streamPicture: (key, mime) => fs.createReadStream(path.join(PLANS, `${key}.${pictureExt(mime)}`)),
  savePicture(key, mime, bytes) {
    fs.writeFileSync(path.join(PLANS, `${key}.${pictureExt(mime)}`), bytes);
  },
  saveSource(key, kind, bytes) {
    fs.writeFileSync(path.join(PLANS, `${key}.${kind}`), bytes);
  },
  saveVector(key, data) {
    fs.writeFileSync(path.join(PLANS, `${key}.vector.json`), JSON.stringify(data));
  },
  loadVector(key) {
    const file = path.join(PLANS, `${key}.vector.json`);
    return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null;
  },
  /** Removes a plan's picture, lines and (for a drawing) its original. */
  remove(key, mime, kind) {
    const files = [path.join(PLANS, `${key}.${pictureExt(mime)}`), path.join(PLANS, `${key}.vector.json`)];
    if (kind && kind !== 'image') files.push(path.join(PLANS, `${key}.${kind}`));
    for (const f of files) if (fs.existsSync(f)) fs.unlinkSync(f);
  },
};

const branchDir = (branchId) => path.join(MAPS, String(Number(branchId)));

/** Map documents as JSON files (used by the Firestore driver; SQL Server keeps them in its tables). */
export const mapFiles = {
  readDraft(branchId) {
    const f = path.join(branchDir(branchId), 'draft.json');
    return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null;
  },
  writeDraft(branchId, doc) {
    fs.mkdirSync(branchDir(branchId), { recursive: true });
    const f = path.join(branchDir(branchId), 'draft.json');
    // Write then rename, so a crash never leaves half a draft.
    fs.writeFileSync(`${f}.tmp`, JSON.stringify(doc));
    fs.renameSync(`${f}.tmp`, f);
  },
  readVersion(branchId, version) {
    const f = path.join(branchDir(branchId), 'versions', `${Number(version)}.json`);
    return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null;
  },
  /** A published version is immutable: writing one that exists is refused. */
  writeVersion(branchId, version, doc) {
    const dir = path.join(branchDir(branchId), 'versions');
    fs.mkdirSync(dir, { recursive: true });
    const f = path.join(dir, `${Number(version)}.json`);
    if (fs.existsSync(f)) throw new Error(`Map version ${version} of branch ${branchId} already exists and cannot be rewritten.`);
    fs.writeFileSync(f, JSON.stringify(doc), { flag: 'wx' });
  },
  /** Drops a version file whose publish failed before it was recorded (never a recorded one). */
  discardUnrecordedVersion(branchId, version) {
    fs.rmSync(path.join(branchDir(branchId), 'versions', Number(version) + '.json'), { force: true });
  },
  /** Removes a branch's map files (when its map is deleted). */
  removeBranch(branchId) {
    fs.rmSync(branchDir(branchId), { recursive: true, force: true });
  },
};

/** Shopper packages (Round 21, P1-08): data/maps/<branch>/packages/<version>.json, under both drivers; never rewritten. */
export const packageFiles = {
  path: (branchId, version) => path.join(branchDir(branchId), 'packages', Number(version) + '.json'),
  has: (branchId, version) => fs.existsSync(path.join(branchDir(branchId), 'packages', Number(version) + '.json')),
  write(branchId, version, json) {
    const dir = path.join(branchDir(branchId), 'packages');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, Number(version) + '.json'), json, { flag: 'wx' });
  },
  read(branchId, version) {
    const f = path.join(branchDir(branchId), 'packages', Number(version) + '.json');
    return fs.existsSync(f) ? fs.readFileSync(f) : null;
  },
  removeBranch(branchId) {
    fs.rmSync(path.join(branchDir(branchId), 'packages'), { recursive: true, force: true });
  },
};

/** Announcement pictures (Round 21): one per announcement, kept with the plans' uploads. */
export const pictures = {
  path: (key, mime) => path.join(PICTURES, key + '.' + pictureExt(mime)),
  has: (key, mime) => fs.existsSync(path.join(PICTURES, key + '.' + pictureExt(mime))),
  save(key, mime, bytes) {
    fs.writeFileSync(path.join(PICTURES, key + '.' + pictureExt(mime)), bytes);
  },
  stream: (key, mime) => fs.createReadStream(path.join(PICTURES, key + '.' + pictureExt(mime))),
  remove(key, mime) {
    fs.rmSync(path.join(PICTURES, key + '.' + pictureExt(mime)), { force: true });
  },
};
