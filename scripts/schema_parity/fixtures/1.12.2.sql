DROP INDEX index_points_on_track_id;
INSERT INTO users (email, settings, created_at, updated_at, visits_redetected_at) VALUES
  ('stamped@example.test', '{"anomaly_rules_recalculation_queued_at": "2026-01-02T00:00:00Z", "anomaly_rules_recalculated_at": "2026-01-03T00:00:00Z", "anomaly_rules_recalculation_failed_at": "2026-01-04T00:00:00Z", "fog_of_war_meters": "50"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('queued@example.test', '{"anomaly_rules_recalculation_queued_at": "2026-01-02T00:00:00Z", "minutes_between_routes": "30"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('recalculated@example.test', '{"anomaly_rules_recalculated_at": "2026-01-03T00:00:00Z"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('failed@example.test', '{"anomaly_rules_recalculation_failed_at": "2026-01-04T00:00:00Z"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('unstamped@example.test', '{"fog_of_war_meters": "100", "anomaly_rules_version": "2"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
