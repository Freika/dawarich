UPDATE pg_index SET indisvalid = false, indisready = false WHERE indexrelid = 'index_notes_on_attachable_and_noted_date'::regclass;
INSERT INTO users (email, created_at, updated_at) VALUES ('notes@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO trips (name, started_at, ended_at, user_id, created_at, updated_at)
  SELECT 'Leipzig', '2026-01-01 00:00:00', '2026-01-03 00:00:00', id, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'notes@example.test';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT user_id, 'Leipzig morning', 'Trip', id, '2026-01-01 08:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM trips WHERE name = 'Leipzig';
INSERT INTO notes (user_id, title, attachable_type, attachable_id, noted_at, created_at, updated_at)
  SELECT user_id, 'Leipzig evening', 'Trip', id, '2026-01-01 18:00:00', '2026-01-10 00:00:00', '2026-01-10 00:00:00' FROM trips WHERE name = 'Leipzig';
