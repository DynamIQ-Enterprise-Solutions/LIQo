-- Round 4: one mall owner (role key: supervisor) per mall admin.
ALTER TABLE users ADD reports_to INT NULL CONSTRAINT fk_users_reports_to REFERENCES users(id);
-- The column is new in this batch, so the index is created through EXEC (resolved at run time).
EXEC('CREATE INDEX ix_users_reports_to ON users(reports_to) WHERE reports_to IS NOT NULL');
