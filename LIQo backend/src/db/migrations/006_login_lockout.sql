-- Auth: lock an account after repeated failed sign-ins.

ALTER TABLE users ADD failed_logins INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD locked_until DATETIME2 NULL;

INSERT INTO platform_settings (setting_key, setting_value) VALUES ('max_login_attempts', '5');
