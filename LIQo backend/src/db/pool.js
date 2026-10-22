import sql from 'mssql';
import { config } from '../config.js';

let poolPromise;

export function getPool() {
  if (!poolPromise) {
    poolPromise = new sql.ConnectionPool({
      server: config.db.server,
      database: config.db.database,
      user: config.db.user,
      password: config.db.password,
      options: {
        encrypt: config.db.encrypt,
        trustServerCertificate: true,
        // SYSDATETIME() is server-local time; read and write dates as local, never as UTC.
        useUTC: false,
      },
      pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
    })
      .connect()
      .catch((err) => {
        // Reset so a later call can retry after the DB comes up.
        poolPromise = undefined;
        throw err;
      });
  }
  return poolPromise;
}

function applyParams(request, params) {
  for (const [key, raw] of Object.entries(params)) {
    if (raw !== null && typeof raw === 'object' && 'type' in raw && 'value' in raw) {
      request.input(key, raw.type, raw.value);
    } else if (raw === null || raw === undefined) {
      request.input(key, sql.NVarChar, null);
    } else {
      request.input(key, raw);
    }
  }
}

/** Run a parameterized query. `params` is an object of { name: value }.
 *  For an explicit SQL type pass { type: sql.Int, value: 3 }. Returns the mssql result. */
export async function query(text, params = {}) {
  const pool = await getPool();
  const request = pool.request();
  applyParams(request, params);
  return request.query(text);
}

/** Run `fn(tx)` inside a transaction. Use txQuery(tx, ...) for statements inside it. */
export async function withTransaction(fn) {
  const pool = await getPool();
  const tx = new sql.Transaction(pool);
  await tx.begin();
  try {
    const result = await fn(tx);
    await tx.commit();
    return result;
  } catch (err) {
    await tx.rollback();
    throw err;
  }
}

export async function txQuery(tx, text, params = {}) {
  const request = new sql.Request(tx);
  applyParams(request, params);
  return request.query(text);
}

export { sql };
