// Every file the server keeps on its own disk (P1-06A, owner decisions
// 2026-10-23: during the internal test, files stay on the server PC under both
// database drivers; Firebase Storage would need the Blaze plan).
//
//   uploads/backdrops/<key>.png|jpg         a plan's picture
//   uploads/backdrops/<key>.dxf|dwg|svg      a drawing's original
//   uploads/backdrops/<key>.vector.json      a drawing's lines and texts
//   data/maps/<branch>/draft.json            a map draft          (Firestore driver)
//   data/maps/<branch>/versions/<n>.json     a published version  (Firestore driver; never rewritten)
//
// Nothing here is served statically; the routes decide who may read what.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = process.env.FILES_ROOT || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const PLANS = path.join(ROOT, 'uploads/backdrops');
const MAPS = path.join(ROOT, 'data/maps');

fs.mkdirSync(PLANS, { recursive: true });

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
  /** Removes a branch's map files (when its map is deleted). */
  removeBranch(branchId) {
    fs.rmSync(branchDir(branchId), { recursive: true, force: true });
  },
};
