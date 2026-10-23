// Driver front (P1-06A): the same functions on SQL Server (mssql/announcements.js) or Firestore
// (firestore/announcements.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/announcements.js') : await import('./mssql/announcements.js');

export const {
  create,
  findById,
  list,
  remove,
  removeBranches,
  review,
  toPublic,
  update,
  setImage,
} = impl;
