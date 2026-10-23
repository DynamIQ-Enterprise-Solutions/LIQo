// Lifts, escalators and stairs marked out of service (Round 21), by branch and
// connector id, kept apart from map versions so a mark survives a republish
// while the connector exists.
import { query, sql } from '../../db/pool.js';

const int = (v) => ({ type: sql.Int, value: v });

export async function list(branchId) {
  const r = await query(
    `SELECT o.connector_id, o.since, o.marked_by, u.full_name AS marked_by_name
       FROM connector_outages o LEFT JOIN users u ON u.id = o.marked_by
      WHERE o.branch_id = @b ORDER BY o.connector_id`,
    { b: int(branchId) },
  );
  return r.recordset.map((x) => ({ connectorId: x.connector_id, since: x.since, markedBy: x.marked_by, markedByName: x.marked_by_name ?? null }));
}

/** Marks a connector out of service; a second mark keeps the first time. Returns true when it was new. */
export async function mark(branchId, connectorId, userId) {
  const r = await query(
    `IF NOT EXISTS (SELECT 1 FROM connector_outages WHERE branch_id = @b AND connector_id = @c)
       INSERT INTO connector_outages (branch_id, connector_id, marked_by) OUTPUT inserted.connector_id VALUES (@b, @c, @u)`,
    { b: int(branchId), c: connectorId, u: int(userId) },
  );
  return (r.recordset?.length ?? 0) > 0;
}

/** Clears a mark. Returns true when there was one. */
export async function clear(branchId, connectorId) {
  const r = await query(`DELETE FROM connector_outages OUTPUT deleted.connector_id WHERE branch_id = @b AND connector_id = @c`, { b: int(branchId), c: connectorId });
  return r.recordset.length > 0;
}

/** Clears the marks whose connector is not in [keepIds] (a new map version without it). Returns the cleared ids. */
export async function clearMissing(branchId, keepIds) {
  const marks = await list(branchId);
  const keep = new Set(keepIds);
  const gone = marks.map((m) => m.connectorId).filter((id) => !keep.has(id));
  for (const id of gone) await clear(branchId, id);
  return gone;
}
