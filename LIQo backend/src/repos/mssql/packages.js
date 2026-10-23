// Shopper package records (Round 21, P1-08): one per published map version.
import { query, sql } from '../../db/pool.js';

const int = (v) => ({ type: sql.Int, value: v });
const toPublic = (x) => (x ? { branchId: x.branch_id, version: x.version, formatVersion: x.format_version, checksum: x.checksum, sizeBytes: x.size_bytes, builtAt: x.built_at } : null);

export async function record({ branchId, version, formatVersion, checksum, sizeBytes }) {
  await query(
    `INSERT INTO map_packages (branch_id, version, format_version, checksum, size_bytes) VALUES (@b, @v, @f, @c, @s)`,
    { b: int(branchId), v: int(version), f: int(formatVersion), c: checksum, s: int(sizeBytes) },
  );
}

export async function find(branchId, version) {
  const r = await query(`SELECT * FROM map_packages WHERE branch_id = @b AND version = @v`, { b: int(branchId), v: int(version) });
  return toPublic(r.recordset[0]);
}

/** The records of these branches' given versions: Map branchId → record. */
export async function forVersions(pairs) {
  const out = new Map();
  for (const { branchId, version } of pairs) {
    const p = await find(branchId, version);
    if (p) out.set(branchId, p);
  }
  return out;
}

export async function removeBranch(branchId) {
  await query(`DELETE FROM map_packages WHERE branch_id = @b`, { b: int(branchId) });
}
