CREATE TABLE IF NOT EXISTS phoenix.import_download_requests (
  import_id bigint NOT NULL,
  source_blob_id bigint NOT NULL,
  requested_at timestamptz NOT NULL,
  event_id uuid NOT NULL,
  PRIMARY KEY (import_id, source_blob_id)
);
