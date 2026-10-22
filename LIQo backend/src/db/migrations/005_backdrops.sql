-- Phase 7: uploaded floor-plan images used as a tracing backdrop (draft only).

CREATE TABLE map_backdrops (
  backdrop_key CHAR(32) NOT NULL PRIMARY KEY,
  branch_id INT NOT NULL CONSTRAINT fk_backdrop_branch REFERENCES branches(id),
  file_name NVARCHAR(80) NOT NULL,
  original_name NVARCHAR(255) NULL,
  mime_type NVARCHAR(60) NOT NULL,
  size_bytes INT NOT NULL,
  width_px INT NOT NULL,
  height_px INT NOT NULL,
  uploaded_by INT NULL,
  uploaded_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX ix_backdrops_branch ON map_backdrops (branch_id);

-- Daily AI/conversion usage, for the platform cap.
CREATE TABLE map_conversions (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  branch_id INT NOT NULL,
  backdrop_key CHAR(32) NOT NULL,
  level_id NVARCHAR(40) NOT NULL,
  used_ai BIT NOT NULL DEFAULT 0,
  wall_count INT NOT NULL DEFAULT 0,
  space_count INT NOT NULL DEFAULT 0,
  requested_by INT NULL,
  requested_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX ix_conversions_day ON map_conversions (requested_at);
