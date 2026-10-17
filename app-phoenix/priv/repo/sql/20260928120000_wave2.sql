CREATE TABLE IF NOT EXISTS phoenix.notification_events (
  id bigserial PRIMARY KEY,
  notification_id bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS phoenix.delivery_claims (
  handler text NOT NULL,
  provider_key text NOT NULL,
  event_id uuid NOT NULL,
  claimed_at timestamptz NOT NULL,
  delivered_at timestamptz,
  PRIMARY KEY (handler, provider_key)
);
CREATE INDEX IF NOT EXISTS delivery_claims_claimed_at ON phoenix.delivery_claims (claimed_at);
CREATE TABLE IF NOT EXISTS phoenix.export_claims (
  export_id bigint PRIMARY KEY,
  event_id uuid NOT NULL,
  claimed_at timestamptz NOT NULL
);
