import { insertAudit } from '../repos/audit.js';
import { redact } from '../utils/redact.js';

const WRITE_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

/**
 * Records write requests on finish. Skipped when the handler already wrote a
 * more specific entry with recordAudit(), and for auth routes which audit
 * themselves.
 */
export function auditWrites(req, res, next) {
  if (!WRITE_METHODS.has(req.method) || req.path.startsWith('/auth')) return next();

  res.on('finish', () => {
    if (res.statusCode >= 400 || res.locals.audited) return;
    const details = {
      body: redact(req.body ?? {}),
      params: req.params ?? {},
      status: res.statusCode,
    };
    insertAudit({
      actorId: req.user?.id ?? null,
      actorEmail: req.user?.email ?? null,
      action: `${req.method} ${req.baseUrl}${req.path}`,
      entityType: null,
      entityId: req.params?.id ?? null,
      details,
      ip: req.ip,
    }).catch((err) => console.error('audit write failed:', err.message));
  });

  next();
}

/** Write a named audit entry from a handler. Marks the request so the generic entry is skipped. */
export async function recordAudit(req, res, { action, entityType, entityId, details }) {
  res.locals.audited = true;
  await insertAudit({
    actorId: req.user?.id ?? null,
    actorEmail: req.user?.email ?? null,
    action,
    entityType,
    entityId,
    details: details == null ? null : redact(details),
    ip: req.ip,
  });
}
