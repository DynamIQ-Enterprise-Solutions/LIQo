// Driver front (Round 21): the same functions on SQL Server (mssql/shopper.js) or Firestore
// (firestore/shopper.js), picked by DB_DRIVER. Both drivers keep these names and return shapes in step.
import { config } from '../config.js';

const impl = config.db.driver === 'firestore' ? await import('./firestore/shopper.js') : await import('./mssql/shopper.js');

export const {
  addCounts,
  countsOf,
  livePicture,
  livePosts,
  publishedBranches,
  storesOf,
} = impl;
