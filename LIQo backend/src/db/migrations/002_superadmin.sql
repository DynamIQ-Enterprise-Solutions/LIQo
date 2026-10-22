-- Phase 2: malls, branches, supervisor and mall admin assignments.

CREATE TABLE malls (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  name NVARCHAR(200) NOT NULL,
  logo_url NVARCHAR(500) NULL,
  is_active BIT NOT NULL DEFAULT 1,
  created_by INT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_malls_name UNIQUE (name)
);

CREATE TABLE branches (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  mall_id INT NOT NULL CONSTRAINT fk_branches_mall REFERENCES malls(id),
  name NVARCHAR(200) NOT NULL,
  logo_url NVARCHAR(500) NULL,
  address NVARCHAR(500) NULL,
  latitude DECIMAL(9,6) NULL,
  longitude DECIMAL(9,6) NULL,
  opening_hours NVARCHAR(300) NULL,
  contact_phone NVARCHAR(50) NULL,
  contact_email NVARCHAR(255) NULL,
  is_active BIT NOT NULL DEFAULT 1,
  created_by INT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_branches_mall_name UNIQUE (mall_id, name)
);

CREATE INDEX ix_branches_mall ON branches (mall_id);

-- A supervisor is assigned to a whole mall (all its branches) or to one branch.
CREATE TABLE supervisor_assignments (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  user_id INT NOT NULL CONSTRAINT fk_supassign_user REFERENCES users(id),
  mall_id INT NULL CONSTRAINT fk_supassign_mall REFERENCES malls(id),
  branch_id INT NULL CONSTRAINT fk_supassign_branch REFERENCES branches(id),
  assigned_by INT NULL,
  assigned_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT ck_supassign_one_target CHECK (
    (mall_id IS NULL AND branch_id IS NOT NULL) OR (mall_id IS NOT NULL AND branch_id IS NULL)
  )
);

CREATE UNIQUE INDEX uq_supassign_mall ON supervisor_assignments (user_id, mall_id) WHERE mall_id IS NOT NULL;
CREATE UNIQUE INDEX uq_supassign_branch ON supervisor_assignments (user_id, branch_id) WHERE branch_id IS NOT NULL;

CREATE TABLE mall_admin_assignments (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  user_id INT NOT NULL CONSTRAINT fk_maassign_user REFERENCES users(id),
  branch_id INT NOT NULL CONSTRAINT fk_maassign_branch REFERENCES branches(id),
  assigned_by INT NULL,
  assigned_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_maassign UNIQUE (user_id, branch_id)
);

CREATE INDEX ix_maassign_branch ON mall_admin_assignments (branch_id);
