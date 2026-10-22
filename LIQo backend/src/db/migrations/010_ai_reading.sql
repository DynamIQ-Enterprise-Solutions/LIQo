-- Round 15 (owner decisions 2026-10-22): floor plans are read by AI through
-- IQGateway. Each run keeps the model it used and what it cost.
ALTER TABLE map_conversions ADD
  model NVARCHAR(100) NULL,
  credits DECIMAL(18, 4) NULL,
  usd DECIMAL(18, 6) NULL,
  crop NVARCHAR(100) NULL;
