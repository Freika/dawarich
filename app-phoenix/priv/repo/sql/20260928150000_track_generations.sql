CREATE TABLE IF NOT EXISTS phoenix.track_generations (
  id uuid PRIMARY KEY,
  user_id bigint NOT NULL,
  mode text NOT NULL CHECK (mode IN ('bulk', 'daily')),
  untracked_only boolean NOT NULL,
  import_id bigint,
  low_priority boolean NOT NULL,
  status text NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
  total_chunks integer NOT NULL CHECK (total_chunks > 0),
  completed_chunks integer NOT NULL DEFAULT 0,
  tracks_created integer NOT NULL DEFAULT 0,
  poll_count integer NOT NULL DEFAULT 0,
  stall_count integer NOT NULL DEFAULT 0,
  seen_completed integer NOT NULL DEFAULT -1,
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS track_generations_created_at_idx ON phoenix.track_generations (created_at);
CREATE TABLE IF NOT EXISTS phoenix.track_generation_chunks (
  generation_id uuid NOT NULL REFERENCES phoenix.track_generations (id) ON DELETE CASCADE,
  chunk_id integer NOT NULL,
  start_ts bigint NOT NULL,
  end_ts bigint NOT NULL,
  buffer_start_ts bigint NOT NULL,
  buffer_end_ts bigint NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed')),
  tracks_created integer NOT NULL DEFAULT 0,
  PRIMARY KEY (generation_id, chunk_id)
);
