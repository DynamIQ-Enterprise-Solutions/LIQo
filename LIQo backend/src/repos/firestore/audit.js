// The audit trail on Firestore (P1-06A). Each entry also bumps the running
// totals the analytics read, never a scan: _daily/<day> { <action>: n } plus
// _actors.<id>.login_success, _branches.<id>.map_edited and _emails.<email>.<action>
// for failed sign-ins (the per-person and per-branch charts).
import { col, docOf, runTx, nextId, all, dayKey, FieldValue, Timestamp } from '../../db/firestore.js';
import { listInMemory } from './util.js';

function cleanIp(ip) {
  if (!ip) return null;
  return ip.startsWith('::ffff:') ? ip.slice(7) : ip;
}

/** The running-total increments for one audit entry. */
function dailyBump({ actorId, actorEmail, action, entityId }) {
  const one = { [action]: FieldValue.increment(1) };
  const out = { ...one };
  if (action === 'login_success' && actorId != null) out._actors = { [actorId]: one };
  if (action === 'map_edited' && entityId != null) out._branches = { [entityId]: one };
  if (action === 'login_failed' || action === 'login_blocked_locked') out._emails = { [actorEmail ? String(actorEmail).toLowerCase() : '(unknown)']: one };
  return out;
}

export async function insertAudit({ actorId, actorEmail, action, entityType, entityId, details, ip }) {
  let detailText = details == null ? null : JSON.stringify(details);
  if (detailText && detailText.length > 4000) detailText = `${detailText.slice(0, 4000)}…[truncated]`;
  await runTx(async (tx) => {
    const id = await nextId('audit_log', tx);
    tx.set(docOf('audit_log', id), {
      id,
      actor_id: actorId ?? null,
      actor_email: actorEmail ?? null,
      action,
      entity_type: entityType ?? null,
      entity_id: entityId == null ? null : String(entityId),
      details: detailText,
      ip: cleanIp(ip),
      created_at: Timestamp.now(),
    });
    tx.set(docOf('_daily', dayKey()), dailyBump({ actorId, actorEmail, action, entityId }), { merge: true });
  });
}

/** Minutes since the actor's last entry with this action on this entity; Infinity when none. */
export async function minutesSinceLast({ action, actorId, entityType, entityId }) {
  const rows = await all(col('audit_log').where('actor_id', '==', Number(actorId)).where('action', '==', action));
  const mine = rows.filter((a) => a.entity_type === entityType && a.entity_id === String(entityId)).sort((a, b) => b.id - a.id);
  if (!mine.length) return Infinity;
  return Math.floor((Date.now() - mine[0].created_at.getTime()) / 60000);
}

function toPublic(row) {
  let details = null;
  if (row.details) {
    try {
      details = JSON.parse(row.details);
    } catch {
      details = row.details;
    }
  }
  return {
    id: row.id,
    actorId: row.actor_id,
    actorEmail: row.actor_email,
    action: row.action,
    entityType: row.entity_type,
    entityId: row.entity_id,
    details,
    ip: row.ip,
    createdAt: row.created_at,
  };
}

export async function list({ search, actor, action, from, to, offset, pageSize, sortColumn, sortOrder }) {
  let q = col('audit_log');
  if (from) q = q.where('created_at', '>=', Timestamp.fromDate(from));
  if (to) q = q.where('created_at', '<', Timestamp.fromDate(to));
  const contains = (v, s) => String(v ?? '').toLowerCase().includes(String(s).toLowerCase());
  const rows = (await all(q)).filter((a) => (!actor || contains(a.actor_email, actor)) && (!action || contains(a.action, action)));
  const { items, totalCount } = listInMemory(rows, { search, searchFields: ['action', 'actor_email', 'entity_type', 'entity_id', 'details'], sortColumn, sortOrder, offset, pageSize });
  return { items: items.map(toPublic), totalCount };
}

/** Distinct action names, for the filter dropdown (from the running totals, not a scan). */
export async function actions() {
  const days = await all(col('_daily'));
  const names = new Set();
  for (const d of days) for (const k of Object.keys(d)) if (!k.startsWith('_')) names.add(k);
  return [...names].sort();
}
