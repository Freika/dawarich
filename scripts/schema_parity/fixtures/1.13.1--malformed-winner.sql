CREATE TABLE "service_settings" ("id" bigserial primary key, "user_id" bigint NOT NULL, "service" integer NOT NULL, "provider" character varying NOT NULL, "config" jsonb DEFAULT '{}' NOT NULL, "credentials" text, "active" boolean DEFAULT FALSE NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_bcdd50bba4" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE INDEX "index_service_settings_on_user_id" ON "service_settings" ("user_id");
CREATE UNIQUE INDEX "index_service_settings_on_user_id_and_service_and_provider" ON "service_settings" ("user_id", "service", "provider");
CREATE UNIQUE INDEX "index_service_settings_on_user_service_active" ON "service_settings" ("user_id", "service") WHERE "active";
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('malformed@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'geoapify', '{}', '{"p":"","h":"headers"}', false, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'malformed@example.test';
