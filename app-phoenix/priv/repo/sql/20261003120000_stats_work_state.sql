CREATE TABLE IF NOT EXISTS phoenix.stats_geocoded_days (
  member text PRIMARY KEY,
  version text NOT NULL,
  due_at bigint NOT NULL
);
CREATE INDEX IF NOT EXISTS stats_geocoded_days_due ON phoenix.stats_geocoded_days (due_at, member COLLATE "C");
CREATE TABLE IF NOT EXISTS phoenix.cursors (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
