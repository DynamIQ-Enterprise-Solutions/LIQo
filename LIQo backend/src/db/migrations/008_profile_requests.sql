-- Round 8: people change their own name and email; non-superadmins send a
-- request that a superadmin approves or rejects.
CREATE TABLE profile_requests (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  user_id INT NOT NULL CONSTRAINT fk_profile_requests_user REFERENCES users(id),
  full_name NVARCHAR(200) NOT NULL,
  email NVARCHAR(255) NOT NULL,
  status NVARCHAR(20) NOT NULL CONSTRAINT df_profile_requests_status DEFAULT 'pending'
    CONSTRAINT ck_profile_requests_status CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  reason NVARCHAR(500) NULL,
  reviewed_by INT NULL,
  reviewed_at DATETIME2 NULL,
  created_at DATETIME2 NOT NULL CONSTRAINT df_profile_requests_created DEFAULT SYSDATETIME()
);

-- One waiting request per person, enforced by the database.
CREATE UNIQUE INDEX ux_profile_requests_one_pending ON profile_requests(user_id) WHERE status = 'pending';
CREATE INDEX ix_profile_requests_status ON profile_requests(status, created_at);
