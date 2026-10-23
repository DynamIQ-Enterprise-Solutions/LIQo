// Driver front (P1-06A): the same functions on SQL Server (mssql/scope.js) or Firestore
// (firestore/scope.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/scope.js') : await import('./mssql/scope.js');

export const {
  branchIdsOfMalls,
  mallAdminBranches,
  storeOwnerStores,
  supervisorAssignments,
} = impl;
