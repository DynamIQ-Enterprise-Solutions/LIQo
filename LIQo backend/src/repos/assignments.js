// Driver front (P1-06A): the same functions on SQL Server (mssql/assignments.js) or Firestore
// (firestore/assignments.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/assignments.js') : await import('./mssql/assignments.js');

export const {
  ONE_BRANCH,
  addMallOwner,
  branchAdmins,
  mallAdminAssignments,
  mallPeople,
  recomputeReportsTo,
  removeMallAdmin,
  removeMallOwner,
  replaceMallAdminAssignments,
  replaceSupervisorAssignments,
  setMallAdminBranches,
  supervisorAssignments,
} = impl;
