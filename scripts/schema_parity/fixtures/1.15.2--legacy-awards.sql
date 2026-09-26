CREATE TABLE "user_achievements" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "earned_at" timestamp(6) NOT NULL, "metadata" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_4efde02858" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE UNIQUE INDEX "index_user_achievements_on_user_id_and_achievement_key" ON "user_achievements" ("user_id", "achievement_key");
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('awardee@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at)
  SELECT id, 'explorer_germany', '2026-01-02 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'awardee@example.test';
