CREATE TABLE IF NOT EXISTS phoenix.job_owners (
  key text PRIMARY KEY,
  owner text NOT NULL DEFAULT 'sidekiq' CHECK (owner IN ('sidekiq', 'oban')),
  pinned boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text NOT NULL DEFAULT 'default'
);
CREATE TABLE IF NOT EXISTS phoenix.job_outbox_replays (
  id bigserial PRIMARY KEY,
  event_id uuid NOT NULL,
  actor text NOT NULL,
  reason text NOT NULL,
  replayed_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS phoenix.processed_commands (
  event_id uuid PRIMARY KEY,
  handler text NOT NULL,
  processed_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS processed_commands_processed_at ON phoenix.processed_commands (processed_at);
CREATE TABLE IF NOT EXISTS phoenix.runtime_nodes (
  node text PRIMARY KEY,
  started_at timestamptz NOT NULL,
  beat_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS phoenix.app_version (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  latest_version text NOT NULL,
  checked_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS phoenix.trip_events (
  id bigserial PRIMARY KEY,
  trip_id bigint NOT NULL,
  kind text NOT NULL CHECK (kind IN ('path', 'distance', 'countries', 'finished')),
  distance_unit text NOT NULL,
  failed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL
);
