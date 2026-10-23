// Driver front (P1-06A): the same functions on SQL Server (mssql/settings.js) or Firestore
// (firestore/settings.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/settings.js') : await import('./mssql/settings.js');

export const {
  DEFAULTS,
  RULES,
  getAll,
  getNumber,
  getText,
  invalidate,
  setMany,
} = impl;
