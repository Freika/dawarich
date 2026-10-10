CREATE INDEX "index_tracks_on_original_path" ON "tracks" USING gist ("original_path");
UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'index_tracks_on_original_path'::regclass;
