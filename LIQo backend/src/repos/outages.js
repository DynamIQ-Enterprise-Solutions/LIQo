// Driver front (Round 21): the same functions on SQL Server (mssql/outages.js) or Firestore
// (firestore/outages.js), picked by DB_DRIVER. Both drivers keep these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/outages.js') : await import('./mssql/outages.js');

export const {
  clear,
  clearMissing,
  list,
  mark,
} = impl;
