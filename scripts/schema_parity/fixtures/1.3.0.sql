ALTER TABLE "points" ADD "motion_data" jsonb DEFAULT '{}' NOT NULL;
DROP INDEX idx_points_user_city;
CREATE INDEX "index_points_on_not_reverse_geocoded" ON "points" ("id") WHERE reverse_geocoded_at IS NULL;
DROP INDEX index_points_on_reverse_geocoded_at;
CREATE INDEX index_points_on_reverse_geocoded_at ON points (city);
