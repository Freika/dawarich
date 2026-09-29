CREATE TABLE IF NOT EXISTS phoenix.rails_commands (
  id bigserial PRIMARY KEY,
  kind text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  attempts integer NOT NULL DEFAULT 0,
  available_at timestamptz NOT NULL DEFAULT now(),
  leased_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS phoenix.rails_commands_dead (
  id bigint PRIMARY KEY,
  kind text NOT NULL,
  payload jsonb NOT NULL,
  attempts integer NOT NULL,
  last_error text NOT NULL,
  created_at timestamptz NOT NULL,
  died_at timestamptz NOT NULL DEFAULT now()
);
