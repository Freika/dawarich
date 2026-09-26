CREATE TABLE "user_achievements" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "earned_at" timestamp(6) NOT NULL, "metadata" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_4efde02858" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_user_achievements_on_user_id_and_achievement_key" ON "user_achievements" ("user_id", "achievement_key");
INSERT INTO users (email, created_at, updated_at, visits_redetected_at, deleted_at) VALUES
  ('collector@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL),
  ('continental@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL),
  ('departed@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-06 00:00:00');
INSERT INTO user_achievements (user_id, achievement_key, earned_at, metadata, created_at, updated_at)
  SELECT id, 'explorer_germany', '2026-01-02 00:00:00', '{"source": "legacy"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'collector@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'country_de', '2026-01-03 00:00:00', '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'collector@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, metadata, created_at, updated_at)
  SELECT id, 'explorer_usa', '2026-01-04 00:00:00', '{"regions": 3}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'collector@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'globetrotter', '2026-01-05 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'collector@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'continent_europe', '2026-01-06 00:00:00', '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'continental@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'explorer_europe', '2026-01-07 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'continental@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'explorer_germany', '2026-01-08 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'continental@example.test';
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'explorer_usa', '2026-01-09 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'departed@example.test';
