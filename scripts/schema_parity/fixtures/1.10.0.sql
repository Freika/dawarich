CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE TABLE "posters" ("id" bigserial primary key, "user_id" bigint NOT NULL, "name" character varying NOT NULL, "status" integer DEFAULT 0 NOT NULL, "settings" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_f1941d801b" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE INDEX "index_posters_on_user_id" ON "posters" ("user_id");
