// Shopper package records on Firestore (Round 21, P1-08): map_packages/<branch>_<version>.
import { col, docOf, one, getDb, Timestamp } from '../../db/firestore.js';

const idOf = (branchId, version) => `${Number(branchId)}_${Number(version)}`;
const toPublic = (x) => (x ? { branchId: x.branch_id, version: x.version, formatVersion: x.format_version, checksum: x.checksum, sizeBytes: x.size_bytes, builtAt: x.built_at } : null);

export async function record({ branchId, version, formatVersion, checksum, sizeBytes }) {
  await docOf('map_packages', idOf(branchId, version)).create({
    branch_id: Number(branchId),
    version: Number(version),
    format_version: formatVersion,
    checksum,
    size_bytes: sizeBytes,
    built_at: Timestamp.now(),
  });
}

export async function find(branchId, version) {
  return toPublic(await one('map_packages', idOf(branchId, version)));
}

export async function forVersions(pairs) {
  const out = new Map();
  for (const { branchId, version } of pairs) {
    const p = await find(branchId, version);
    if (p) out.set(branchId, p);
  }
  return out;
}

export async function removeBranch(branchId) {
  const rows = await col('map_packages').where('branch_id', '==', Number(branchId)).get();
  const batch = getDb().batch();
  rows.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
}

