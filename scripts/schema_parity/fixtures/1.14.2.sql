ALTER TABLE "families" ADD "access_until" timestamp(6);
INSERT INTO users (email, settings, created_at, updated_at, visits_redetected_at) VALUES ('retired@example.test', '{"max_gap_minutes_in_city": "120", "fog_of_war_meters": "50"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, settings, created_at, updated_at, visits_redetected_at) VALUES ('current@example.test', '{"fog_of_war_meters": "100", "minutes_between_routes": "30"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
