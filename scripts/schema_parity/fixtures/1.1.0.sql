ALTER TABLE "users" ADD "deleted_at" timestamp(6);
CREATE INDEX "index_users_on_deleted_at" ON "users" ("deleted_at");
INSERT INTO users (email, created_at, updated_at) VALUES ('first@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, deleted_at) VALUES ('deleted@example.test', '2026-01-02 00:00:00', '2026-01-02 00:00:00', '2026-01-05 00:00:00');
INSERT INTO users (email, created_at, updated_at) VALUES ('third@example.test', '2026-01-03 00:00:00', '2026-01-03 00:00:00');
UPDATE users SET api_key = 'first-key', updated_at = '2026-01-04 00:00:00' WHERE email = 'first@example.test';
