// Driver front (P1-06A): the same functions on SQL Server (mssql/owners.js) or Firestore
// (firestore/owners.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/owners.js') : await import('./mssql/owners.js');

export const {
  assign,
  list,
  ownersForStore,
  storesForOwner,
  storesForOwners,
  unassign,
} = impl;
