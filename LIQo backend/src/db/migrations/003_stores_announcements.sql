-- Phase 3 + 4: announcements, branch option lists, stores, store owners, store-space links.

CREATE TABLE branch_options (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  branch_id INT NOT NULL CONSTRAINT fk_bopt_branch REFERENCES branches(id),
  kind NVARCHAR(30) NOT NULL
    CONSTRAINT ck_bopt_kind CHECK (kind IN ('store_category','unit_type','floor_label')),
  name NVARCHAR(100) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_bopt UNIQUE (branch_id, kind, name)
);

CREATE TABLE stores (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  branch_id INT NOT NULL CONSTRAINT fk_stores_branch REFERENCES branches(id),
  name NVARCHAR(200) NOT NULL,
  category_id INT NULL CONSTRAINT fk_stores_category REFERENCES branch_options(id),
  logo_url NVARCHAR(500) NULL,
  description NVARCHAR(1000) NULL,
  opening_hours NVARCHAR(300) NULL,
  contact_phone NVARCHAR(50) NULL,
  contact_email NVARCHAR(255) NULL,
  is_active BIT NOT NULL DEFAULT 1,
  created_by INT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_stores_branch_name UNIQUE (branch_id, name)
);

CREATE INDEX ix_stores_branch ON stores (branch_id);

CREATE TABLE store_owner_assignments (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  user_id INT NOT NULL CONSTRAINT fk_soa_user REFERENCES users(id),
  store_id INT NOT NULL CONSTRAINT fk_soa_store REFERENCES stores(id),
  assigned_by INT NULL,
  assigned_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_soa UNIQUE (user_id, store_id)
);

CREATE INDEX ix_soa_store ON store_owner_assignments (store_id);

-- Store ↔ map space links. Kept apart from the map geometry document.
CREATE TABLE store_spaces (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  store_id INT NOT NULL CONSTRAINT fk_ss_store REFERENCES stores(id),
  branch_id INT NOT NULL CONSTRAINT fk_ss_branch REFERENCES branches(id),
  space_key NVARCHAR(40) NOT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_ss UNIQUE (store_id, space_key)
);

CREATE INDEX ix_ss_branch_space ON store_spaces (branch_id, space_key);

CREATE TABLE announcements (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  title NVARCHAR(200) NOT NULL,
  body NVARCHAR(MAX) NOT NULL,
  image_url NVARCHAR(500) NULL,
  starts_on DATE NOT NULL,
  ends_on DATE NOT NULL,
  status NVARCHAR(20) NOT NULL
    CONSTRAINT ck_ann_status CHECK (status IN ('pending','approved','rejected')),
  store_id INT NULL CONSTRAINT fk_ann_store REFERENCES stores(id),
  created_by INT NOT NULL CONSTRAINT fk_ann_user REFERENCES users(id),
  created_role NVARCHAR(20) NOT NULL,
  reviewed_by INT NULL,
  reviewed_at DATETIME2 NULL,
  reject_reason NVARCHAR(500) NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT ck_ann_dates CHECK (ends_on >= starts_on)
);

CREATE INDEX ix_ann_status_dates ON announcements (status, starts_on, ends_on);

CREATE TABLE announcement_branches (
  announcement_id INT NOT NULL CONSTRAINT fk_ab_ann REFERENCES announcements(id) ON DELETE CASCADE,
  branch_id INT NOT NULL CONSTRAINT fk_ab_branch REFERENCES branches(id),
  CONSTRAINT pk_ab PRIMARY KEY (announcement_id, branch_id)
);

CREATE INDEX ix_ab_branch ON announcement_branches (branch_id);
