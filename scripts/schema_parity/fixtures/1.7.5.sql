ALTER TABLE "track_segments" ADD "corrected_at" timestamp(6);
CREATE INDEX "index_track_segments_on_corrected_at" ON "track_segments" ("corrected_at") WHERE corrected_at IS NOT NULL;
