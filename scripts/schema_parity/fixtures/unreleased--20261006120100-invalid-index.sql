ALTER TABLE tracks ADD COLUMN IF NOT EXISTS matched_path geometry(MultiLineString,4326);
CREATE INDEX IF NOT EXISTS index_tracks_on_matched_path ON tracks USING gist(matched_path) WHERE matched_path IS NOT NULL;
UPDATE pg_index SET indisvalid=false WHERE indexrelid='index_tracks_on_matched_path'::regclass;
