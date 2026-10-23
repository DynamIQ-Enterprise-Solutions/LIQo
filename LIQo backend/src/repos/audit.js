// Driver front (P1-06A): the same functions on SQL Server (mssql/audit.js) or Firestore
// (firestore/audit.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/audit.js') : await import('./mssql/audit.js');

export const {
  actions,
  insertAudit,
  list,
  minutesSinceLast,
} = impl;
