// Driver front (P1-06A): the same functions on SQL Server (mssql/maps.js) or Firestore
// (firestore/maps.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/maps.js') : await import('./mssql/maps.js');

export const {
  LOCK_MINUTES,
  acquireLock,
  create,
  findByBranch,
  forceReleaseLock,
  holdsLock,
  publish,
  publishedLayout,
  releaseLock,
  remove,
  saveDraft,
  statusForBranches,
  toPublic,
  versionLayout,
  versions,
} = impl;
