// Driver front (Round 21): the same functions on SQL Server (mssql/packages.js) or Firestore
// (firestore/packages.js), picked by DB_DRIVER. Both drivers keep these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/packages.js') : await import('./mssql/packages.js');

export const {
  find,
  forVersions,
  record,
  removeBranch,
} = impl;
