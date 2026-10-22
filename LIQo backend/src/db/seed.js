// Creates the first superadmin. Safe to run more than once.
import { runMigrations } from './migrate.js';
import * as users from '../repos/users.js';
import { hashPassword } from '../utils/password.js';

const EMAIL = 'admin@liqo.local';
const PASSWORD = 'Admin@123';

async function main() {
  await runMigrations();
  if (await users.findByEmail(EMAIL)) {
    console.log(`superadmin ${EMAIL} already exists`);
    return;
  }
  await users.create({
    email: EMAIL,
    passwordHash: await hashPassword(PASSWORD),
    fullName: 'LIQo Superadmin',
    role: 'superadmin',
    mustChange: false,
  });
  console.log(`seeded superadmin ${EMAIL} / ${PASSWORD}`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
