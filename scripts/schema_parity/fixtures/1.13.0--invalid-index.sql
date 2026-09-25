UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'index_points_on_visit_id'::regclass;
UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'idx_points_user_country_name'::regclass;
UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'index_points_on_user_id_timestamp_lonlat'::regclass;
