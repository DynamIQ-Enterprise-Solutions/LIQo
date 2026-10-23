-- Round 19 (owner decisions 2026-10-23).
--
-- AI credits per mall admin: a share of the IQGateway wallet set aside for one
-- admin. Giving credits moves no money; the wallet only goes down when a reading
-- is paid. Every change is a ledger row.
CREATE TABLE ai_credit_balances (
  user_id INT NOT NULL CONSTRAINT pk_ai_credit_balances PRIMARY KEY
    CONSTRAINT fk_ai_credit_balances_user REFERENCES users(id),
  balance DECIMAL(12, 4) NOT NULL CONSTRAINT df_ai_credit_balances_balance DEFAULT 0,
  -- The balance right after the last top-up: the full mark of the admin's credit bar.
  full_mark DECIMAL(12, 4) NULL,
  updated_at DATETIME2 NOT NULL CONSTRAINT df_ai_credit_balances_updated DEFAULT SYSDATETIME()
);

CREATE TABLE ai_credit_requests (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  user_id INT NOT NULL CONSTRAINT fk_ai_credit_requests_user REFERENCES users(id),
  amount DECIMAL(12, 4) NOT NULL CONSTRAINT ck_ai_credit_requests_amount CHECK (amount > 0),
  status NVARCHAR(20) NOT NULL CONSTRAINT df_ai_credit_requests_status DEFAULT 'pending'
    CONSTRAINT ck_ai_credit_requests_status CHECK (status IN ('pending', 'approved', 'declined', 'cancelled')),
  decided_amount DECIMAL(12, 4) NULL,
  decided_by INT NULL CONSTRAINT fk_ai_credit_requests_decider REFERENCES users(id),
  decline_reason NVARCHAR(300) NULL,
  created_at DATETIME2 NOT NULL CONSTRAINT df_ai_credit_requests_created DEFAULT SYSDATETIME(),
  decided_at DATETIME2 NULL
);

-- One open request per admin, enforced by the database.
CREATE UNIQUE INDEX ux_ai_credit_requests_one_pending ON ai_credit_requests(user_id) WHERE status = 'pending';
CREATE INDEX ix_ai_credit_requests_status ON ai_credit_requests(status, created_at);

CREATE TABLE ai_credit_ledger (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  user_id INT NOT NULL CONSTRAINT fk_ai_credit_ledger_user REFERENCES users(id),
  delta DECIMAL(12, 4) NOT NULL,
  balance_after DECIMAL(12, 4) NOT NULL,
  kind NVARCHAR(20) NOT NULL
    CONSTRAINT ck_ai_credit_ledger_kind CHECK (kind IN ('start', 'grant', 'remove', 'reading', 'returned', 'request')),
  conversion_id INT NULL CONSTRAINT fk_ai_credit_ledger_conversion REFERENCES map_conversions(id),
  request_id INT NULL CONSTRAINT fk_ai_credit_ledger_request REFERENCES ai_credit_requests(id),
  actor_id INT NULL CONSTRAINT fk_ai_credit_ledger_actor REFERENCES users(id),
  note NVARCHAR(200) NULL,
  created_at DATETIME2 NOT NULL CONSTRAINT df_ai_credit_ledger_created DEFAULT SYSDATETIME()
);

CREATE INDEX ix_ai_credit_ledger_user ON ai_credit_ledger(user_id, created_at);
CREATE INDEX ix_ai_credit_ledger_day ON ai_credit_ledger(created_at);

-- Problem reports: mall owners, mall admins and store owners tell the
-- superadmin about a problem; both sides talk in a thread until it is
-- resolved or closed.
CREATE TABLE problem_reports (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  reporter_id INT NOT NULL CONSTRAINT fk_problem_reports_reporter REFERENCES users(id),
  type NVARCHAR(20) NOT NULL
    CONSTRAINT ck_problem_reports_type CHECK (type IN ('broken', 'wrong_data', 'question', 'idea')),
  subject NVARCHAR(120) NOT NULL,
  body NVARCHAR(2000) NOT NULL,
  page_path NVARCHAR(300) NULL,
  status NVARCHAR(20) NOT NULL CONSTRAINT df_problem_reports_status DEFAULT 'new'
    CONSTRAINT ck_problem_reports_status CHECK (status IN ('new', 'in_progress', 'resolved', 'closed')),
  created_at DATETIME2 NOT NULL CONSTRAINT df_problem_reports_created DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL CONSTRAINT df_problem_reports_updated DEFAULT SYSDATETIME(),
  closed_at DATETIME2 NULL,
  closed_by INT NULL CONSTRAINT fk_problem_reports_closer REFERENCES users(id)
);

CREATE INDEX ix_problem_reports_status ON problem_reports(status, updated_at);
CREATE INDEX ix_problem_reports_reporter ON problem_reports(reporter_id, created_at);

CREATE TABLE problem_report_messages (
  id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  report_id INT NOT NULL CONSTRAINT fk_problem_report_messages_report REFERENCES problem_reports(id),
  author_id INT NOT NULL CONSTRAINT fk_problem_report_messages_author REFERENCES users(id),
  body NVARCHAR(2000) NOT NULL,
  created_at DATETIME2 NOT NULL CONSTRAINT df_problem_report_messages_created DEFAULT SYSDATETIME()
);

CREATE INDEX ix_problem_report_messages_report ON problem_report_messages(report_id, created_at);
