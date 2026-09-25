CREATE UNIQUE INDEX "index_users_on_provider_and_uid_present" ON "users" ("provider", "uid") WHERE provider IS NOT NULL AND uid IS NOT NULL;
DROP INDEX index_users_on_provider_and_uid;
