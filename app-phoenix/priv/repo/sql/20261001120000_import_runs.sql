CREATE TABLE IF NOT EXISTS phoenix.import_runs (
  import_id bigint PRIMARY KEY,
  user_id bigint NOT NULL,
  event_id uuid NOT NULL,
  job_id bigint NOT NULL,
  attempt integer NOT NULL CHECK (attempt > 0),
  token uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
