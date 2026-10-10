DROP INDEX index_notes_on_attachable_and_noted_date;
INSERT INTO users (email, created_at, updated_at) VALUES ('notes@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO trips (name, started_at, ended_at, user_id, created_at, updated_at)
  SELECT 'Leipzig', '2026-01-01 00:00:00', '2026-01-03 00:00:00', id, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'notes@example.test';
INSERT INTO trips (name, started_at, ended_at, user_id, created_at, updated_at)
  SELECT 'Dresden', '2026-01-05 00:00:00', '2026-01-06 00:00:00', id, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'notes@example.test';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT user_id, 'Leipzig morning', 'Trip', id, '2026-01-01 08:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM trips WHERE name = 'Leipzig';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT user_id, 'Leipzig evening', 'Trip', id, '2026-01-01 18:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM trips WHERE name = 'Leipzig';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT user_id, 'Leipzig next day', 'Trip', id, '2026-01-02 08:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM trips WHERE name = 'Leipzig';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT user_id, 'Dresden one', 'Trip', id, '2026-01-05 09:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM trips WHERE name = 'Dresden';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT user_id, 'Dresden two', 'Trip', id, '2026-01-05 10:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM trips WHERE name = 'Dresden';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT user_id, 'Dresden three', 'Trip', id, '2026-01-05 11:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM trips WHERE name = 'Dresden';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT id, 'Loose one', NULL, NULL, '2026-01-01 08:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM users WHERE email = 'notes@example.test';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT id, 'Loose two', NULL, NULL, '2026-01-01 09:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM users WHERE email = 'notes@example.test';
