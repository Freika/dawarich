CREATE TABLE "achievement_progresses" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "state" jsonb DEFAULT '{}' NOT NULL, "sharing_enabled" boolean DEFAULT FALSE NOT NULL, "sharing_uuid" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_103a2f87f0" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_achievement_progresses_on_user_id_and_achievement_key" ON "achievement_progresses" ("user_id", "achievement_key");
CREATE UNIQUE INDEX "index_achievement_progresses_on_sharing_uuid" ON "achievement_progresses" ("sharing_uuid");
CREATE TABLE "user_achievements" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "earned_at" timestamp(6) NOT NULL, "metadata" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_4efde02858" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_user_achievements_on_user_id_and_achievement_key" ON "user_achievements" ("user_id", "achievement_key");
CREATE TABLE "regions" ("id" bigserial primary key, "code" character varying NOT NULL, "geom" geometry(MULTIPOLYGON,4326) NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
CREATE UNIQUE INDEX "index_regions_on_code" ON "regions" ("code");
CREATE INDEX "index_regions_on_geom" ON "regions" USING gist ("geom");
CREATE TABLE "achievement_unlock_events" ("id" bigserial primary key, "user_id" bigint NOT NULL, "kind" character varying NOT NULL, "key" character varying NOT NULL, "claimed_at" timestamp(6), "claim_token" character varying, "seen_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_ed0477f0f9" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE);
CREATE INDEX "index_achievement_unlock_events_on_user_id" ON "achievement_unlock_events" ("user_id");
CREATE UNIQUE INDEX "index_achievement_unlock_events_on_user_kind_key" ON "achievement_unlock_events" ("user_id", "kind", "key");
CREATE INDEX "index_achievement_unlock_events_pending" ON "achievement_unlock_events" ("user_id", "id") WHERE seen_at IS NULL;
INSERT INTO regions (code, geom, created_at, updated_at) VALUES
  ('DE-BE', ST_Multi(ST_GeomFromText('POLYGON((13 52, 14 52, 14 53, 13 53, 13 52))', 4326)), '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('DE', ST_Multi(ST_GeomFromText('POLYGON((5 47, 15 47, 15 55, 5 55, 5 47))', 4326)), '2026-01-01 00:00:00', '2026-01-01 00:00:00');
