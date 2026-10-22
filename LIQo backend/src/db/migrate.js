import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getPool, sql } from './pool.js';

const migrationsDir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'migrations');

/** Apply every migration file in src/db/migrations not yet recorded, in filename order.
 *  Each file runs in its own transaction. Applied files are never re-run or edited. */
export async function runMigrations() {
  const pool = await getPool();

  await pool.request().batch(`
    IF OBJECT_ID('schema_migrations') IS NULL
      CREATE TABLE schema_migrations (
        filename NVARCHAR(255) NOT NULL PRIMARY KEY,
        applied_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
      );
  `);

  const appliedRows = (await pool.request().query('SELECT filename FROM schema_migrations')).recordset;
  const applied = new Set(appliedRows.map((r) => r.filename));

  const files = fs
    .readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  let count = 0;
  for (const file of files) {
    if (applied.has(file)) continue;
    const text = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    const tx = new sql.Transaction(pool);
    await tx.begin();
    try {
      await new sql.Request(tx).batch(text);
      await new sql.Request(tx).input('f', file).query('INSERT INTO schema_migrations (filename) VALUES (@f)');
      await tx.commit();
      console.log(`migrated ${file}`);
      count += 1;
    } catch (err) {
      await tx.rollback();
      throw new Error(`migration ${file} failed: ${err.message}`);
    }
  }
  if (count === 0) console.log('migrations up to date');
  return count;
}
