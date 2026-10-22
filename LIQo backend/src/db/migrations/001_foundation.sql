-- Phase 1 foundation: users, platform settings, audit log.

CREATE TABLE users (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  email NVARCHAR(255) NOT NULL UNIQUE,
  password_hash NVARCHAR(255) NOT NULL,
  full_name NVARCHAR(200) NOT NULL,
  role NVARCHAR(20) NOT NULL
    CONSTRAINT ck_users_role CHECK (role IN ('superadmin','supervisor','mall_admin','store_owner')),
  is_active BIT NOT NULL DEFAULT 1,
  must_change_password BIT NOT NULL DEFAULT 1,
  last_login_at DATETIME2 NULL,
  created_by INT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE platform_settings (
  setting_key NVARCHAR(100) NOT NULL PRIMARY KEY,
  setting_value NVARCHAR(500) NOT NULL,
  updated_by INT NULL,
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

INSERT INTO platform_settings (setting_key, setting_value) VALUES
  ('min_password_length', '8'),
  ('ai_file_size_mb', '15'),
  ('ai_daily_cap', '20'),
  ('default_announcement_days', '7'),
  ('session_timeout_hours', '8');

CREATE TABLE audit_log (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  actor_id INT NULL,
  actor_email NVARCHAR(255) NULL,
  action NVARCHAR(100) NOT NULL,
  entity_type NVARCHAR(100) NULL,
  entity_id NVARCHAR(100) NULL,
  details NVARCHAR(MAX) NULL,
  ip NVARCHAR(64) NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX ix_audit_created_at ON audit_log (created_at DESC);
CREATE INDEX ix_audit_actor ON audit_log (actor_id);
