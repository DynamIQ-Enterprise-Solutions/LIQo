-- Round 21: the shopper service (P1-07), owner decisions 2026-10-23
-- (docs/shopper-hybrid-decisions.md §3, docs/round-21-shopper-service.md).

-- Opening hours per weekday plus special days, Philippine time, as JSON
-- {week:[{day,open,close}], specials:[{date, closed|open/close, note?}]}.
-- The old free-text opening_hours stays as a read-only note.
ALTER TABLE branches ADD hours_json NVARCHAR(MAX) NULL;
ALTER TABLE stores ADD hours_json NVARCHAR(MAX) NULL;

-- Store status, set by the mall admin or the store owner. Directions are given whatever it is.
ALTER TABLE stores ADD status NVARCHAR(20) NOT NULL CONSTRAINT df_stores_status DEFAULT 'open'
  CONSTRAINT ck_stores_status CHECK (status IN ('open', 'temporarily_closed', 'being_repaired', 'opening_soon'));

-- The shopper app's category for each store-category option.
ALTER TABLE branch_options ADD app_category NVARCHAR(20) NOT NULL CONSTRAINT df_branch_options_app_category DEFAULT 'other'
  CONSTRAINT ck_branch_options_app_category CHECK (app_category IN ('food', 'fashion', 'tech', 'books', 'services', 'other'));

-- Branch location from a pasted Google Maps link; the pin's place name is shown back to confirm.
ALTER TABLE branches ADD maps_link NVARCHAR(500) NULL;
ALTER TABLE branches ADD place_name NVARCHAR(200) NULL;

-- One uploaded picture per announcement (stored on disk with the plans). image_url stays for old rows.
ALTER TABLE announcements ADD image_key CHAR(32) NULL;
ALTER TABLE announcements ADD image_mime NVARCHAR(30) NULL;

-- Lifts, escalators and stairs marked out of service, by branch and connector id (kept apart from map versions).
CREATE TABLE connector_outages (
  branch_id INT NOT NULL CONSTRAINT fk_connector_outages_branch REFERENCES branches(id),
  connector_id NVARCHAR(40) NOT NULL,
  since DATETIME2 NOT NULL CONSTRAINT df_connector_outages_since DEFAULT SYSDATETIME(),
  marked_by INT NULL CONSTRAINT fk_connector_outages_user REFERENCES users(id),
  CONSTRAINT pk_connector_outages PRIMARY KEY (branch_id, connector_id)
);

-- Anonymous shopper counts, added up per day (no person, device or IP).
-- dim is the place id, the category or the search word ('' when none).
CREATE TABLE shopper_counts (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  day DATE NOT NULL,
  branch_id INT NOT NULL CONSTRAINT fk_shopper_counts_branch REFERENCES branches(id),
  event NVARCHAR(30) NOT NULL,
  store_id INT NULL,
  dim NVARCHAR(60) NOT NULL CONSTRAINT df_shopper_counts_dim DEFAULT '',
  n INT NOT NULL
);
CREATE UNIQUE INDEX ux_shopper_counts_key ON shopper_counts(day, branch_id, event, store_id, dim);
