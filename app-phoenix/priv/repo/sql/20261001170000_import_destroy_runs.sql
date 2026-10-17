CREATE TABLE IF NOT EXISTS phoenix.import_destroy_runs (
  import_id bigint PRIMARY KEY,
  user_id bigint NOT NULL,
  event_id uuid NOT NULL,
  job_id bigint,
  attempt integer CHECK (attempt > 0),
  token uuid,
  phase text NOT NULL DEFAULT 'requested' CHECK (phase IN ('requested','deleting','removed','handback')),
  native_fallback boolean NOT NULL DEFAULT false,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
