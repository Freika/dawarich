CREATE TABLE IF NOT EXISTS phoenix.import_archive_children (
  parent_id bigint NOT NULL,
  blob_id bigint NOT NULL,
  entry_name text NOT NULL,
  user_id bigint NOT NULL,
  event_id uuid NOT NULL,
  child_id bigint,
  storage_key text,
  phase text NOT NULL DEFAULT 'building',
  error_message text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (parent_id, blob_id, entry_name),
  CHECK (phase IN ('building','created','skipped','built','failed','queued','removed'))
);
