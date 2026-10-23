// Driver front (P1-06A): the same functions on SQL Server (mssql/reports.js) or Firestore
// (firestore/reports.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/reports.js') : await import('./mssql/reports.js');

export const {
  addMessage,
  create,
  findById,
  list,
  messages,
  setStatus,
  waitingCount,
} = impl;
