// Driver front (P1-06A): the same functions on SQL Server (mssql/branches.js) or Firestore
// (firestore/branches.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/branches.js') : await import('./mssql/branches.js');

export const {
  create,
  findById,
  impact,
  list,
  setActive,
  toPublic,
  update,
  updateInfo,
} = impl;
