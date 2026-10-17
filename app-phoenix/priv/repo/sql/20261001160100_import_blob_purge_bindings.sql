ALTER TABLE phoenix.import_blob_purges DROP CONSTRAINT import_blob_purges_pkey;
ALTER TABLE phoenix.import_blob_purges ADD PRIMARY KEY (blob_id, import_id, user_id, source_blob_id);
