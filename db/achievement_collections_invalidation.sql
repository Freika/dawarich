SET LOCAL lock_timeout = '5s';
CREATE OR REPLACE FUNCTION invalidate_achievement_collections() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE source_sql text; has_decimal boolean; has_source boolean;
BEGIN
  IF current_setting('dawarich.defer_revisions', true) = 'on' THEN RETURN NULL; END IF;
  IF TG_OP = 'INSERT' THEN
    source_sql := 'SELECT user_id FROM new_rows';
  ELSIF TG_OP = 'DELETE' THEN
    source_sql := 'SELECT user_id FROM old_rows';
  ELSE
    source_sql := 'SELECT user_id FROM new_rows UNION SELECT user_id FROM old_rows';
  END IF;
  IF TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'points' THEN
    -- altitude_decimal is absent where the decimal migration never ran (#3969);
    -- source_id until 20260816150000's deferred ALTER lands (#3972).
    has_decimal := EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = TG_RELID AND attname = 'altitude_decimal' AND NOT attisdropped);
    has_source := EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = TG_RELID AND attname = 'source_id' AND NOT attisdropped);
    source_sql := 'SELECT DISTINCT user_id FROM (SELECT n.user_id FROM new_rows n JOIN old_rows o USING (id) WHERE (n.user_id,n.timestamp,n.lonlat::text,n.anomaly,n.track_id,n.altitude,' || CASE WHEN has_decimal THEN 'n.altitude_decimal,' ELSE '' END || 'n.accuracy,n.velocity,n.motion_data,n.tracker_id' || CASE WHEN has_source THEN ',n.source_id' ELSE '' END || ') IS DISTINCT FROM (o.user_id,o.timestamp,o.lonlat::text,o.anomaly,o.track_id,o.altitude,' || CASE WHEN has_decimal THEN 'o.altitude_decimal,' ELSE '' END || 'o.accuracy,o.velocity,o.motion_data,o.tracker_id' || CASE WHEN has_source THEN ',o.source_id' ELSE '' END || ') UNION SELECT o.user_id FROM old_rows o JOIN new_rows n USING(id) WHERE o.user_id IS DISTINCT FROM n.user_id) changed';
  END IF;
  IF TG_TABLE_NAME = 'track_segments' THEN
    IF TG_OP = 'INSERT' THEN
      source_sql := 'SELECT t.user_id FROM new_rows r JOIN tracks t ON t.id = r.track_id';
    ELSIF TG_OP = 'DELETE' THEN
      source_sql := 'SELECT t.user_id FROM old_rows r JOIN tracks t ON t.id = r.track_id';
    ELSE
      source_sql := 'SELECT t.user_id FROM new_rows r JOIN tracks t ON t.id = r.track_id UNION SELECT t.user_id FROM old_rows r JOIN tracks t ON t.id = r.track_id';
    END IF;
  END IF;
  IF TG_TABLE_NAME = 'taggings' THEN
    IF TG_OP = 'INSERT' THEN
      source_sql := 'SELECT p.user_id FROM new_rows r JOIN places p ON p.id = r.taggable_id WHERE r.taggable_type = ''Place''';
    ELSIF TG_OP = 'DELETE' THEN
      source_sql := 'SELECT p.user_id FROM old_rows r JOIN places p ON p.id = r.taggable_id WHERE r.taggable_type = ''Place''';
    ELSE
      source_sql := 'SELECT p.user_id FROM new_rows r JOIN places p ON p.id = r.taggable_id WHERE r.taggable_type = ''Place'' UNION SELECT p.user_id FROM old_rows r JOIN places p ON p.id = r.taggable_id WHERE r.taggable_type = ''Place''';
    END IF;
  END IF;
  EXECUTE 'INSERT INTO achievement_collection_states (user_id, revision, published_revision, created_at, updated_at)
    SELECT DISTINCT s.user_id, 1, 0, now(), now() FROM (' || source_sql || ') s JOIN users u ON u.id = s.user_id ORDER BY s.user_id
    ON CONFLICT (user_id) DO UPDATE SET revision = achievement_collection_states.revision + 1, updated_at = now()';
  RETURN NULL;
END;
$$;

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['visits', 'places', 'achievement_selections', 'points', 'tracks', 'track_segments', 'tags', 'taggings', 'achievement_city_selections'] LOOP
    CONTINUE WHEN to_regclass(table_name) IS NULL;
    EXECUTE format('DROP TRIGGER IF EXISTS achievement_collections_insert ON %I', table_name);
    EXECUTE format('CREATE TRIGGER achievement_collections_insert AFTER INSERT ON %I REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_achievement_collections()', table_name);
    EXECUTE format('DROP TRIGGER IF EXISTS achievement_collections_update ON %I', table_name);
    EXECUTE format('CREATE TRIGGER achievement_collections_update AFTER UPDATE ON %I REFERENCING NEW TABLE AS new_rows OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_achievement_collections()', table_name);
    EXECUTE format('DROP TRIGGER IF EXISTS achievement_collections_delete ON %I', table_name);
    EXECUTE format('CREATE TRIGGER achievement_collections_delete AFTER DELETE ON %I REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION invalidate_achievement_collections()', table_name);
  END LOOP;
END;
$$;
