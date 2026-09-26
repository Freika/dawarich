CREATE TABLE "achievement_progresses" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "state" jsonb DEFAULT '{}' NOT NULL, "sharing_enabled" boolean DEFAULT FALSE NOT NULL, "sharing_uuid" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_103a2f87f0" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_achievement_progresses_on_user_id_and_achievement_key" ON "achievement_progresses" ("user_id", "achievement_key");
CREATE UNIQUE INDEX "index_achievement_progresses_on_sharing_uuid" ON "achievement_progresses" ("sharing_uuid");
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('colliding@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'explorer_germany', '{"earned": {"DE-BE": "2026-01-02T00:00:00Z"}}', TRUE, 'share-legacy-de', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'colliding@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'country_de', '{"earned": {"DE-BE": "2026-01-03T00:00:00Z"}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'colliding@example.test';
