SET LOCAL lock_timeout = '5s';
-- Statement triggers cover bulk writes (upsert_all/update_all/delete_all) as well
-- as individual records. Only the affected owners are dirtied, once per statement.
CREATE OR REPLACE FUNCTION invalidate_exploration() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE owners_sql text;
BEGIN
  IF current_setting('dawarich.defer_revisions', true) = 'on' THEN RETURN NULL; END IF;
  IF TG_TABLE_NAME = 'track_segments' THEN
    owners_sql := CASE TG_OP
      WHEN 'INSERT' THEN 'SELECT DISTINCT tracks.user_id FROM new_rows r JOIN tracks ON tracks.id = r.track_id'
      WHEN 'DELETE' THEN 'SELECT DISTINCT tracks.user_id FROM old_rows r JOIN tracks ON tracks.id = r.track_id'
      ELSE 'SELECT DISTINCT tracks.user_id FROM (SELECT track_id FROM new_rows UNION SELECT track_id FROM old_rows) r JOIN tracks ON tracks.id = r.track_id' END;
  ELSIF TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'points' THEN
    owners_sql := 'SELECT DISTINCT user_id FROM (SELECT n.user_id FROM new_rows n JOIN old_rows o USING (id) WHERE (n.user_id,n.timestamp,n.lonlat::text,n.anomaly,n.track_id,n.altitude,n.altitude_decimal,n.accuracy,n.velocity,n.motion_data) IS DISTINCT FROM (o.user_id,o.timestamp,o.lonlat::text,o.anomaly,o.track_id,o.altitude,o.altitude_decimal,o.accuracy,o.velocity,o.motion_data) UNION SELECT o.user_id FROM old_rows o JOIN new_rows n USING(id) WHERE o.user_id IS DISTINCT FROM n.user_id) changed';
  ELSE
    owners_sql := CASE TG_OP WHEN 'INSERT' THEN 'SELECT DISTINCT user_id FROM new_rows'
      WHEN 'DELETE' THEN 'SELECT DISTINCT user_id FROM old_rows'
      ELSE 'SELECT user_id FROM new_rows UNION SELECT user_id FROM old_rows' END;
  END IF;
  EXECUTE 'INSERT INTO exploration_states(user_id,revision,published_revision,created_at,updated_at)
    SELECT u.id,1,0,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP FROM users u JOIN (' || owners_sql || ') affected ON u.id=affected.user_id ORDER BY u.id
    ON CONFLICT(user_id) DO UPDATE SET revision=exploration_states.revision+1,updated_at=CURRENT_TIMESTAMP';
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS exploration_points_insert ON points;
CREATE TRIGGER exploration_points_insert AFTER INSERT ON points REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
DROP TRIGGER IF EXISTS exploration_points_update ON points;
CREATE TRIGGER exploration_points_update AFTER UPDATE ON points REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
DROP TRIGGER IF EXISTS exploration_points_delete ON points;
CREATE TRIGGER exploration_points_delete AFTER DELETE ON points REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
DROP TRIGGER IF EXISTS exploration_tracks_insert ON tracks;
CREATE TRIGGER exploration_tracks_insert AFTER INSERT ON tracks REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
DROP TRIGGER IF EXISTS exploration_tracks_update ON tracks;
CREATE TRIGGER exploration_tracks_update AFTER UPDATE ON tracks REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
DROP TRIGGER IF EXISTS exploration_tracks_delete ON tracks;
CREATE TRIGGER exploration_tracks_delete AFTER DELETE ON tracks REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
DROP TRIGGER IF EXISTS exploration_track_segments_insert ON track_segments;
CREATE TRIGGER exploration_track_segments_insert AFTER INSERT ON track_segments REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
DROP TRIGGER IF EXISTS exploration_track_segments_update ON track_segments;
CREATE TRIGGER exploration_track_segments_update AFTER UPDATE ON track_segments REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
DROP TRIGGER IF EXISTS exploration_track_segments_delete ON track_segments;
CREATE TRIGGER exploration_track_segments_delete AFTER DELETE ON track_segments REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_exploration();
