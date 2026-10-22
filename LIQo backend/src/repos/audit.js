import { query, sql } from '../db/pool.js';

function cleanIp(ip) {
  if (!ip) return null;
  return ip.startsWith('::ffff:') ? ip.slice(7) : ip;
}

export async function insertAudit({ actorId, actorEmail, action, entityType, entityId, details, ip }) {
  let detailText = details == null ? null : JSON.stringify(details);
  if (detailText && detailText.length > 4000) detailText = `${detailText.slice(0, 4000)}…[truncated]`;
  await query(
    `INSERT INTO audit_log (actor_id, actor_email, action, entity_type, entity_id, details, ip)
     VALUES (@actorId, @actorEmail, @action, @entityType, @entityId, @details, @ip)`,
    {
      actorId: actorId == null ? null : { type: sql.Int, value: actorId },
      actorEmail: actorEmail ?? null,
      action,
      entityType: entityType ?? null,
      entityId: entityId == null ? null : String(entityId),
      details: detailText,
      ip: cleanIp(ip),
    },
  );
}

/** Minutes since the actor's last entry with this action on this entity; Infinity when none. */
export async function minutesSinceLast({ action, actorId, entityType, entityId }) {
  const r = await query(
    `SELECT TOP 1 DATEDIFF(minute, a.created_at, SYSDATETIME()) AS m FROM audit_log a
      WHERE a.action = @action AND a.actor_id = @actor AND a.entity_type = @type AND a.entity_id = @id
      ORDER BY a.id DESC`,
    { action, actor: { type: sql.Int, value: actorId }, type: entityType, id: String(entityId) },
  );
  return r.recordset[0]?.m ?? Infinity;
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
  const where = [];
  const params = { offset: { type: sql.Int, value: offset }, limit: { type: sql.Int, value: pageSize } };
  if (search) {
    where.push('(a.action LIKE @search OR a.actor_email LIKE @search OR a.entity_type LIKE @search OR a.entity_id LIKE @search OR a.details LIKE @search)');
    params.search = `%${search}%`;
  }
  if (actor) {
    where.push('a.actor_email LIKE @actor');
    params.actor = `%${actor}%`;
  }
  if (action) {
    where.push('a.action LIKE @action');
    params.action = `%${action}%`;
  }
  if (from) {
    where.push('a.created_at >= @from');
    params.from = { type: sql.DateTime2, value: from };
  }
  if (to) {
    where.push('a.created_at < @to');
    params.to = { type: sql.DateTime2, value: to };
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const total = (await query(`SELECT COUNT(*) AS n FROM audit_log a ${whereSql}`, params)).recordset[0].n;
  const rows = (
    await query(
      `SELECT a.id, a.actor_id, a.actor_email, a.action, a.entity_type, a.entity_id, a.details, a.ip, a.created_at
         FROM audit_log a ${whereSql}
        ORDER BY ${sortColumn} ${sortOrder}
       OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
      params,
    )
  ).recordset;
  return { items: rows.map(toPublic), totalCount: total };
}

/** Distinct action names, for the filter dropdown. */
export async function actions() {
  const r = await query('SELECT DISTINCT action FROM audit_log ORDER BY action');
  return r.recordset.map((x) => x.action);
}
