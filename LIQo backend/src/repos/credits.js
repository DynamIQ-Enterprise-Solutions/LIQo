// Driver front (P1-06A): the same functions on SQL Server (mssql/credits.js) or Firestore
// (firestore/credits.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/credits.js') : await import('./mssql/credits.js');

export const {
  adminRows,
  avgCost,
  balanceOf,
  cancelOpenRequest,
  change,
  createRequest,
  decideRequest,
  findRequest,
  givenTotal,
  history,
  isActiveMallAdmin,
  latestRequestFor,
  listRequests,
  pendingRequestCount,
  usageSeries,
  withCreditsLock,
} = impl;
