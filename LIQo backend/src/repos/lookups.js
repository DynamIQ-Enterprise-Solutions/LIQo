// Driver front (P1-06A): the same functions on SQL Server (mssql/lookups.js) or Firestore
// (firestore/lookups.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/lookups.js') : await import('./mssql/lookups.js');

export const {
  LOOKUPS,
  lookup,
} = impl;
