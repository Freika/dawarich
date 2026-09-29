CREATE UNIQUE INDEX "idx_visits_user_started_at_place_unique" ON "visits" ("user_id", "started_at", "place_id");
CREATE UNIQUE INDEX "idx_track_segments_track_start_index_unique" ON "track_segments" ("track_id", "start_index");
CREATE UNIQUE INDEX idx_places_user_external_place_id ON places (user_id, ((geodata ->> 'external_place_id'))) WHERE (geodata ->> 'external_place_id') IS NOT NULL;
