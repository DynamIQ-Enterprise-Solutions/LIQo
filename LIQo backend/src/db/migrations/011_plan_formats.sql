-- Round 16 (owner decisions 2026-10-22): plans may also be SVG, DXF or DWG.
-- The picture people see is still a PNG; vector plans also keep the original
-- file and its unit, which gives an exact scale (metres per picture pixel).
ALTER TABLE map_backdrops ADD
  source_kind NVARCHAR(10) NOT NULL CONSTRAINT df_backdrop_kind DEFAULT 'image',
  source_file NVARCHAR(80) NULL,
  units NVARCHAR(10) NULL,
  mpp_from_units DECIMAL(18, 10) NULL;
