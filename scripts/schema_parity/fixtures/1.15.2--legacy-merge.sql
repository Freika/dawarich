CREATE TABLE "achievement_progresses" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "state" jsonb DEFAULT '{}' NOT NULL, "sharing_enabled" boolean DEFAULT FALSE NOT NULL, "sharing_uuid" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_103a2f87f0" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_achievement_progresses_on_user_id_and_achievement_key" ON "achievement_progresses" ("user_id", "achievement_key");
CREATE UNIQUE INDEX "index_achievement_progresses_on_sharing_uuid" ON "achievement_progresses" ("sharing_uuid");
INSERT INTO users (email, created_at, updated_at, visits_redetected_at, deleted_at) VALUES
  ('merger@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL),
  ('fresh@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL),
  ('first-seen@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL),
  ('departed@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-06 00:00:00');
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'world_traveler', '{"earned": {"JP-13": "2026-02-02T00:00:00Z"}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'first-seen@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'exploration', '{"earned": {"DE-BE": "2026-01-15T00:00:00Z", "AT-9": "2026-02-01T00:00:00Z", "PL-MZ": "2026-01-01T00:00:00Z"}, "dwell": {"DE-BE": 3}, "cursor": 7}', '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'merger@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'explorer_germany', '{"earned": {"DE-BE": "2026-03-01T00:00:00Z", "DE-BY": "2026-01-05T00:00:00Z", "IT-25": "2026-06-01T00:00:00Z"}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'merger@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'globetrotter', '{"visited": 3}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'fresh@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'explorer_europe', '{"earned": {"DE-BE": "2026-01-10T00:00:00Z", "FR-IDF": "2026-04-01T00:00:00Z", "DE-BY": "2026-01-05T00:00:00Z", "IT-25": "2026-06-01T00:00:00.000Z"}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'merger@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'border_hopper', '{"earned": {"AT-9": "2026-01-20T00:00:00Z", "PL-MZ": "2026-05-01T00:00:00Z"}, "other": 1}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'merger@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'country_fr', '{"earned": {"FR-IDF": "2025-12-01T00:00:00Z"}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'merger@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'exploration', '{"earned": {"NL-NH": "2026-03-03T00:00:00Z"}, "dwell": {}, "cursor": 0}', '2026-01-01 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'departed@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at)
  SELECT id, 'explorer_usa', '{"earned": {"US-NY": "2026-02-03T00:00:00Z", "NL-NH": "2026-03-04T00:00:00Z"}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'departed@example.test';
