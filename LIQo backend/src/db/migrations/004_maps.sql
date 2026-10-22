-- Phase 6: one map document per branch, immutable published versions, an edit lock.

CREATE TABLE maps (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  branch_id INT NOT NULL CONSTRAINT fk_maps_branch REFERENCES branches(id),
  draft_json NVARCHAR(MAX) NULL,
  draft_version INT NOT NULL DEFAULT 0,
  published_version_id INT NULL,
  lock_user_id INT NULL,
  lock_expires_at DATETIME2 NULL,
  created_by INT NULL,
  updated_by INT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_maps_branch UNIQUE (branch_id)
);

CREATE TABLE map_versions (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  map_id INT NOT NULL CONSTRAINT fk_mapver_map REFERENCES maps(id),
  version INT NOT NULL,
  layout_json NVARCHAR(MAX) NOT NULL,
  space_count INT NOT NULL DEFAULT 0,
  note NVARCHAR(200) NULL,
  published_by INT NULL,
  published_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_mapver UNIQUE (map_id, version)
);

ALTER TABLE maps ADD CONSTRAINT fk_maps_published FOREIGN KEY (published_version_id) REFERENCES map_versions(id);
