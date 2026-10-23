// Driver front (P1-06A): the same functions on SQL Server (mssql/analytics.js) or Firestore
// (firestore/analytics.js), picked by DB_DRIVER. Routes import this file; both drivers keep
// these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/analytics.js') : await import('./mssql/analytics.js');

export const {
  PERIODS,
  accounts,
  activity,
  announcements,
  maps,
  overview,
  security,
  stores,
} = impl;
