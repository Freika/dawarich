ALTER TABLE "users" ADD "deleted_at" timestamp(6);
CREATE INDEX users_deleted_at_custom ON users (deleted_at);
