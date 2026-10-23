// Driver front (P1-06A): the same functions on SQL Server (mssql/backdrops.js) or Firestore
// (firestore/backdrops.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/backdrops.js') : await import('./mssql/backdrops.js');

export const {
  countForBranch,
  find,
  insert,
  listForBranch,
  recordConversion,
  remove,
  setUnit,
} = impl;
