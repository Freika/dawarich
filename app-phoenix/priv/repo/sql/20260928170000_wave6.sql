CREATE TABLE IF NOT EXISTS phoenix.release_operations (
  id uuid PRIMARY KEY,
  command_type text NOT NULL,
  cursor jsonb NOT NULL,
  status text NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed')),
  error text,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);
CREATE INDEX IF NOT EXISTS release_operations_status ON phoenix.release_operations (status, updated_at);
CREATE TABLE IF NOT EXISTS phoenix.raw_data_archive_chunks (
  archive_id bigint PRIMARY KEY,
  user_id bigint NOT NULL,
  storage_key text NOT NULL,
  phase text NOT NULL CHECK (phase IN ('reserved', 'attached', 'verified')),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS raw_data_archive_chunks_user ON phoenix.raw_data_archive_chunks (user_id, updated_at);
