// Driver front (P1-06A): the same functions on SQL Server (mssql/options.js) or Firestore
// (firestore/options.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/options.js') : await import('./mssql/options.js');

export const {
  KINDS,
  create,
  findById,
  list,
  remove,
  setActive,
  update,
} = impl;
