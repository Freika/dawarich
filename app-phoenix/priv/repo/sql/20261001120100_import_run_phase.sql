ALTER TABLE phoenix.import_runs ADD COLUMN IF NOT EXISTS phase text NOT NULL DEFAULT 'processing' CHECK (phase IN ('processing','terminal'));
ALTER TABLE phoenix.import_runs ADD COLUMN IF NOT EXISTS attachment_snapshot jsonb;
