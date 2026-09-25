ALTER TABLE "places" ADD CONSTRAINT places_user_id_not_null CHECK (user_id IS NOT NULL) NOT VALID;
ALTER TABLE "places" ALTER COLUMN "user_id" SET NOT NULL;
CREATE TABLE "route_videos" ("id" bigserial primary key, "user_id" bigint NOT NULL, "name" character varying NOT NULL, "status" integer DEFAULT 0 NOT NULL, "settings" jsonb DEFAULT '{}' NOT NULL, "expired_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_02b56b6dae"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
);
CREATE INDEX "index_route_videos_on_user_id_and_created_at" ON "route_videos" ("user_id", "created_at");
INSERT INTO users (email, settings, created_at, updated_at, visits_redetected_at) VALUES
  ('stamped@example.test', '{"anomaly_rules_recalculation_queued_at": "2026-01-02T00:00:00Z", "anomaly_rules_recalculated_at": "2026-01-03T00:00:00Z", "anomaly_rules_recalculation_failed_at": "2026-01-04T00:00:00Z", "fog_of_war_meters": "50"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('queued@example.test', '{"anomaly_rules_recalculation_queued_at": "2026-01-02T00:00:00Z", "minutes_between_routes": "30"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('recalculated@example.test', '{"anomaly_rules_recalculated_at": "2026-01-03T00:00:00Z"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('failed@example.test', '{"anomaly_rules_recalculation_failed_at": "2026-01-04T00:00:00Z"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('unstamped@example.test', '{"fog_of_war_meters": "100", "anomaly_rules_version": "2"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO point_sources (digest, created_at, updated_at) VALUES ('0123456789abcdef0123456789abcdef', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
