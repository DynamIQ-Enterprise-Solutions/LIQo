// Driver front (P1-06A): the same functions on SQL Server (mssql/profileRequests.js) or Firestore
// (firestore/profileRequests.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/profileRequests.js') : await import('./mssql/profileRequests.js');

export const {
  approve,
  cancelForUser,
  create,
  decide,
  emailPendingForOther,
  findById,
  latestForUser,
  list,
  toPublic,
} = impl;
