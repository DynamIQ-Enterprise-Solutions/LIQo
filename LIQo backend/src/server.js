import { config } from './config.js';
import { getPool } from './db/pool.js';
import { runMigrations } from './db/migrate.js';
import { createApp } from './app.js';

/** Checks the database answers before taking requests (SQL Server or Firestore, by DB_DRIVER). */
async function connect() {
  if (config.db.driver === 'firestore') {
    const { col } = await import('./db/firestore.js');
    await col('platform_settings').limit(1).get();
    const where = process.env.FIRESTORE_EMULATOR_HOST ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}` : `project ${process.env.FIREBASE_PROJECT_ID || '(from the key file)'}`;
    return `Firestore connected (${where})`;
  }
  await getPool();
  return `DB connected (${config.db.server}/${config.db.database} as ${config.db.user})`;
}

async function main() {
  try {
    console.log(await connect());
  } catch (err) {
    console.error(`Cannot connect to the database: ${err.message}`);
    process.exit(1);
  }

  await runMigrations();

  const app = createApp();
  app.listen(config.port, () => {
    console.log(`LIQo API listening on ${config.port}`);
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
