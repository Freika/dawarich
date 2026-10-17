DROP INDEX index_points_on_country_id;
CREATE INDEX index_points_on_country_id ON points (import_id);
DROP INDEX index_points_on_archived_uncleared;
DROP INDEX index_points_on_archived_true;
ALTER TABLE "points" ADD "altitude_decimal" decimal(10,2);
ALTER TABLE "points" ADD "anomaly" boolean;
CREATE INDEX "index_points_on_not_anomaly" ON "points" ("anomaly") WHERE anomaly IS NOT TRUE;
ALTER TABLE "imports" ADD "demo" boolean DEFAULT FALSE NOT NULL;
