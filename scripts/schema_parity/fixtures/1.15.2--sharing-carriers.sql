CREATE TABLE "achievement_progresses" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "state" jsonb DEFAULT '{}' NOT NULL, "sharing_enabled" boolean DEFAULT FALSE NOT NULL, "sharing_uuid" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_103a2f87f0" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_achievement_progresses_on_user_id_and_achievement_key" ON "achievement_progresses" ("user_id", "achievement_key");
CREATE UNIQUE INDEX "index_achievement_progresses_on_sharing_uuid" ON "achievement_progresses" ("sharing_uuid");
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES
  ('sharer@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('blank-uuid@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'explorer_germany', '{"earned": {"DE-BE": "2026-01-02T00:00:00Z"}}', TRUE, 'share-de', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'sharer@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'border_hopper', '{"earned": {"AT-9": "2026-01-03T00:00:00Z"}, "hops": 2}', FALSE, 'share-bh', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'sharer@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'explorer_usa', '{"earned": {"US-NY": "2026-01-04T00:00:00Z"}}', FALSE, ' ', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'sharer@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'explorer_europe', '{}', TRUE, NULL, '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'sharer@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'world_traveler', '{"earned": {"JP-13": "2026-01-05T00:00:00Z"}}', FALSE, NULL, '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'sharer@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'globetrotter', '{}', TRUE, 'share-gt', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'sharer@example.test';
INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at)
  SELECT id, 'explorer_germany', '{"earned": {"DE-HH": "2026-01-06T00:00:00Z"}}', FALSE, '', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'blank-uuid@example.test';
