// Driver front (P1-06A): the same functions on SQL Server (mssql/malls.js) or Firestore
// (firestore/malls.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/malls.js') : await import('./mssql/malls.js');

export const {
  create,
  findById,
  impact,
  list,
  setActive,
  toPublic,
  update,
} = impl;
