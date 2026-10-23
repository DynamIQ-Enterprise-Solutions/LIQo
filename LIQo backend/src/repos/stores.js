// Driver front (P1-06A): the same functions on SQL Server (mssql/stores.js) or Firestore
// (firestore/stores.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/stores.js') : await import('./mssql/stores.js');

export const {
  branchOfOwnedActiveStore,
  create,
  findById,
  list,
  namesForBranch,
  setActive,
  setSpaces,
  spaceLinksForBranch,
  spacesFor,
  toPublic,
  update,
  setHours,
  setStatus,
} = impl;
