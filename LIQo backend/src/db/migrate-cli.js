import { runMigrations } from './migrate.js';

runMigrations()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
