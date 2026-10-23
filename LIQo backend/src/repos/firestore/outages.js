// Out-of-service marks on Firestore (Round 21): doc id <branch>_<connector>.
import { col, docOf, runTx, all, Timestamp } from '../../db/firestore.js';
import { byId, compare } from './util.js';

const idOf = (branchId, connectorId) => `${Number(branchId)}_${connectorId}`;

export async function list(branchId) {
  const [rows, users] = await Promise.all([all(col('connector_outages').where('branch_id', '==', Number(branchId))), all(col('users'))]);
  const u = byId(users);
  return rows
    .sort((a, b) => compare(a.connector_id, b.connector_id))
    .map((x) => ({ connectorId: x.connector_id, since: x.since, markedBy: x.marked_by ?? null, markedByName: u.get(x.marked_by)?.full_name ?? null }));
}

/** Marks a connector out of service; a second mark keeps the first time. Returns true when it was new. */
export async function mark(branchId, connectorId, userId) {
  return runTx(async (tx) => {
    const ref = docOf('connector_outages', idOf(branchId, connectorId));
    if ((await tx.get(ref)).exists) return false;
    tx.set(ref, { branch_id: Number(branchId), connector_id: connectorId, since: Timestamp.now(), marked_by: userId ?? null });
    return true;
  });
}

/** Clears a mark. Returns true when there was one. */
export async function clear(branchId, connectorId) {
  return runTx(async (tx) => {
    const ref = docOf('connector_outages', idOf(branchId, connectorId));
    if (!(await tx.get(ref)).exists) return false;
    tx.delete(ref);
    return true;
  });
}

/** Clears the marks whose connector is not in [keepIds]. Returns the cleared ids. */
export async function clearMissing(branchId, keepIds) {
  const keep = new Set(keepIds);
  const gone = (await list(branchId)).map((m) => m.connectorId).filter((id) => !keep.has(id));
  for (const id of gone) await clear(branchId, id);
  return gone;
}
