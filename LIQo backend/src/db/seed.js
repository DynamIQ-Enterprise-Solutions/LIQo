// Creates the first superadmin. Safe to run more than once.
// --must-change: the password must be changed at the first sign-in (the deployed
// system, owner decision 2026-10-23; the local one keeps signing in directly).
import { runMigrations } from './migrate.js';
import * as users from '../repos/users.js';
import { hashPassword } from '../utils/password.js';

const EMAIL = 'admin@liqo.local';
const PASSWORD = 'Admin@123';
const MUST_CHANGE = process.argv.includes('--must-change');

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
    mustChange: MUST_CHANGE,
  });
  console.log(`seeded superadmin ${EMAIL} / ${PASSWORD}${MUST_CHANGE ? ' (must be changed at the first sign-in)' : ''}`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
