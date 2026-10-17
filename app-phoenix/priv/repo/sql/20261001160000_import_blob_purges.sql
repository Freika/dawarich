CREATE TABLE IF NOT EXISTS phoenix.import_blob_purges (
  blob_id bigint PRIMARY KEY,
  import_id bigint NOT NULL,
  user_id bigint NOT NULL,
  source_blob_id bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (blob_id > 0 AND import_id > 0 AND user_id > 0 AND source_blob_id > 0)
);
