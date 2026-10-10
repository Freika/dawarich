ALTER TABLE notes DROP COLUMN title, DROP COLUMN body, DROP COLUMN attachable_type, DROP COLUMN attachable_id, DROP COLUMN noted_at, DROP COLUMN lonlat;
INSERT INTO users (email, created_at, updated_at) VALUES ('notes@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO notes (user_id, created_at, updated_at)
  SELECT id, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'notes@example.test';
