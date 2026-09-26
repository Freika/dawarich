CREATE TABLE "achievement_progresses" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "state" jsonb DEFAULT '{}' NOT NULL, "sharing_enabled" boolean DEFAULT FALSE NOT NULL, "sharing_uuid" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_103a2f87f0" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_achievement_progresses_on_user_id_and_achievement_key" ON "achievement_progresses" ("user_id", "achievement_key");
CREATE UNIQUE INDEX "index_achievement_progresses_on_sharing_uuid" ON "achievement_progresses" ("sharing_uuid");
CREATE TABLE "user_achievements" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "earned_at" timestamp(6) NOT NULL, "metadata" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_4efde02858" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_user_achievements_on_user_id_and_achievement_key" ON "user_achievements" ("user_id", "achievement_key");
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('settled@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'exploration', '{"earned": {"DE-BE": "2026-01-10T00:00:00Z"}, "dwell": {"DE-BE": 2}, "cursor": 4}', FALSE, NULL, '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'settled@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'country_de', '{"earned": {"DE-BE": "2026-01-10T00:00:00Z"}}', TRUE, 'share-country-de', '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'settled@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'country_de', '2026-01-11 00:00:00', '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'settled@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'continent_europe', '2026-01-12 00:00:00', '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'settled@example.test';
