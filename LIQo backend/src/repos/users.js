// Driver front (P1-06A): the same functions on SQL Server (mssql/users.js) or Firestore
// (firestore/users.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/users.js') : await import('./mssql/users.js');

export const {
  LOCK_MINUTES,
  clearFailedLogins,
  create,
  deactivateKeepingASuperadmin,
  findByEmail,
  findByFullName,
  findById,
  list,
  recordFailedLogin,
  setActive,
  setPassword,
  toPublic,
  updateLastLogin,
  updateProfile,
} = impl;
