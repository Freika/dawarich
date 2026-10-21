ALTER TABLE "track_segments" ADD "start_at" timestamptz;
ALTER TABLE "track_segments" ADD "end_at" timestamptz;
ALTER TABLE "track_segments" ADD "path" geometry(LINESTRING,4326);
ALTER TABLE "track_segments" ADD "confidence_score" float;
CREATE UNIQUE INDEX "idx_track_segments_track_start_at_unique" ON "track_segments" ("track_id", "start_at") WHERE start_at IS NOT NULL;
UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'idx_track_segments_track_start_at_unique'::regclass;
