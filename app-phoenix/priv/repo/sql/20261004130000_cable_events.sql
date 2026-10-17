CREATE TABLE phoenix.cable_streams (
  namespace text PRIMARY KEY,
  last_seq bigint NOT NULL DEFAULT 0,
  retired_through bigint NOT NULL DEFAULT 0,
  CONSTRAINT cable_streams_bounds CHECK (0 <= retired_through AND retired_through <= last_seq)
);
CREATE TABLE phoenix.cable_events (
  namespace text NOT NULL REFERENCES phoenix.cable_streams(namespace),
  seq bigint NOT NULL CHECK (seq > 0),
  channel text NOT NULL,
  payload bytea NOT NULL,
  created_at timestamptz NOT NULL,
  observed_at timestamptz,
  PRIMARY KEY (namespace, seq)
);
