ALTER TABLE phoenix.import_handoffs ADD COLUMN IF NOT EXISTS native_fallback boolean NOT NULL DEFAULT false;
