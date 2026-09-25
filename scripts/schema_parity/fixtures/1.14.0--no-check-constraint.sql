INSERT INTO schema_migrations (version) VALUES ('20260815100000');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('owner@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO places (name, longitude, latitude, user_id, created_at, updated_at)
  SELECT 'Owned cafe', 12.373, 51.340, id, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'owner@example.test';
