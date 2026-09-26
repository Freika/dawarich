ALTER TABLE points DROP CONSTRAINT fk_rails_98d7bdf4ad;
ALTER TABLE points ADD CONSTRAINT archive_fk_a FOREIGN KEY (raw_data_archive_id) REFERENCES points_raw_data_archives (id) ON DELETE SET NULL NOT VALID;
ALTER TABLE points ADD CONSTRAINT archive_fk_b FOREIGN KEY (raw_data_archive_id) REFERENCES points_raw_data_archives (id) NOT VALID;
