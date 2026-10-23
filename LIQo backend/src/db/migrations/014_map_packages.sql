-- Round 21 (P1-08): the shopper package built at each publish. The package
-- itself is a file on the server PC (data/maps/<branch>/packages/<version>.json,
-- never rewritten); this row records what the directory tells phones about it.
CREATE TABLE map_packages (
  branch_id INT NOT NULL CONSTRAINT fk_map_packages_branch REFERENCES branches(id),
  version INT NOT NULL,
  format_version INT NOT NULL,
  checksum CHAR(64) NOT NULL,
  size_bytes INT NOT NULL,
  built_at DATETIME2 NOT NULL CONSTRAINT df_map_packages_built DEFAULT SYSDATETIME(),
  CONSTRAINT pk_map_packages PRIMARY KEY (branch_id, version)
);
