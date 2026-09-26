CREATE TABLE "achievement_progresses" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "state" jsonb DEFAULT '{}' NOT NULL, "sharing_enabled" boolean DEFAULT FALSE NOT NULL, "sharing_uuid" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_103a2f87f0" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_achievement_progresses_on_user_id_and_achievement_key" ON "achievement_progresses" ("user_id", "achievement_key");
CREATE UNIQUE INDEX "index_achievement_progresses_on_sharing_uuid" ON "achievement_progresses" ("sharing_uuid");
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES
  ('floats@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('fresh-floats@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'exploration', '{"earned": {"AT-9": 10000000000000000.0}, "dwell": {"AT-9": 2}, "cursor": 3}', '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'floats@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'explorer_germany', '{"earned": {"DE-BE": 0.00005, "AT-9": 20000000000000000.0}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'floats@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'explorer_usa', '{"earned": {"US-NY": 1.5, "NL-NH": 1767225600.0, "FR-IDF": 0.30000000000000004}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'fresh-floats@example.test';
