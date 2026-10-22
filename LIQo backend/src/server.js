import { config } from './config.js';
import { getPool } from './db/pool.js';
import { runMigrations } from './db/migrate.js';
import { createApp } from './app.js';

async function main() {
  try {
    await getPool();
    console.log(`DB connected (${config.db.server}/${config.db.database} as ${config.db.user})`);
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
