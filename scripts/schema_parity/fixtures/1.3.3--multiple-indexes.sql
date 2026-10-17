CREATE INDEX index_points_on_user_id_unarchived ON points (user_id) WHERE raw_data_archived = false;
