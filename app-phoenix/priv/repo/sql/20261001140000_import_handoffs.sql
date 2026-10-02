CREATE TABLE IF NOT EXISTS phoenix.import_handoffs (
  event_id uuid PRIMARY KEY,
  import_id bigint NOT NULL,
  user_id bigint NOT NULL,
  time_zone text NOT NULL,
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','completed','forwarded')),
  forwarded_event_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
