CREATE TABLE "notes" ("id" bigserial primary key, "user_id" bigint NOT NULL, "title" character varying, "body" text, "lonlat" geography(POINT,4326), "attachable_type" character varying, "attachable_id" bigint, "noted_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_7f2323ad43" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE INDEX "index_notes_on_user_id" ON "notes" ("user_id");
CREATE INDEX "index_notes_on_attachable_type_and_attachable_id" ON "notes" ("attachable_type", "attachable_id");
CREATE INDEX "index_notes_on_lonlat" ON "notes" USING gist ("lonlat");
CREATE INDEX "index_notes_on_user_id_and_noted_at" ON "notes" ("user_id", "noted_at");
CREATE UNIQUE INDEX index_notes_on_attachable_and_noted_date ON notes (attachable_type, attachable_id, (CAST(noted_at AS date))) WHERE attachable_id IS NOT NULL;
CREATE TABLE "shared_links" ("id" uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY, "user_id" bigint NOT NULL, "resource_type" integer NOT NULL, "resource_id" bigint, "name" character varying(255) NOT NULL, "magic_phrase" character varying(255), "expires_at" timestamp(6), "revoked_at" timestamp(6), "settings" jsonb DEFAULT '{}' NOT NULL, "view_count" integer DEFAULT 0 NOT NULL, "last_accessed_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_1b04e35c4c" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE);
CREATE INDEX "index_shared_links_on_user_id" ON "shared_links" ("user_id");
CREATE INDEX "index_shared_links_on_resource_type_and_resource_id" ON "shared_links" ("resource_type", "resource_id") WHERE resource_id IS NOT NULL;
CREATE INDEX "index_shared_links_active_by_user" ON "shared_links" ("user_id") WHERE revoked_at IS NULL;
CREATE TABLE "flights" ("id" bigserial primary key, "user_id" bigint NOT NULL, "external_id" integer NOT NULL, "flight_date" date, "date_precision" character varying DEFAULT 'day' NOT NULL, "departure_time" timestamp(6), "arrival_time" timestamp(6), "from_code" character varying, "from_name" character varying, "from_lat" float, "from_lon" float, "to_code" character varying, "to_name" character varying, "to_lat" float, "to_lon" float, "airline_name" character varying, "airline_iata" character varying, "aircraft_name" character varying, "aircraft_reg" character varying, "flight_number" character varying, "seat" character varying, "seat_class" character varying, "note" text, "distance_km" float, "raw" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_f23525dbb0" FOREIGN KEY ("user_id") REFERENCES "users" ("id"));
CREATE INDEX "index_flights_on_user_id" ON "flights" ("user_id");
CREATE UNIQUE INDEX "index_flights_on_user_id_and_external_id" ON "flights" ("user_id", "external_id");
CREATE INDEX "index_flights_on_user_id_and_departure_time" ON "flights" ("user_id", "departure_time");
INSERT INTO users (email, created_at, updated_at) VALUES ('traveller@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO trips (name, started_at, ended_at, user_id, created_at, updated_at)
  SELECT 'Leipzig', '2026-01-01 00:00:00', '2026-01-03 00:00:00', id, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'traveller@example.test';
INSERT INTO trips (name, started_at, ended_at, user_id, created_at, updated_at)
  SELECT 'Dresden', '2026-02-01 00:00:00', '2026-02-03 00:00:00', id, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'traveller@example.test';
INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
  SELECT 'notes', '<div>Leipzig notes</div>', 'Trip', id, '2026-01-04 00:00:00', '2026-01-04 00:00:00' FROM trips WHERE name = 'Leipzig';
INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
  SELECT 'description', '<div>Dresden description</div>', 'Trip', id, '2026-02-04 00:00:00', '2026-02-04 00:00:00' FROM trips WHERE name = 'Dresden';
INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
  SELECT 'notes', '<div>User notes</div>', 'User', id, '2026-01-05 00:00:00', '2026-01-05 00:00:00' FROM users WHERE email = 'traveller@example.test';
INSERT INTO countries (name, iso_a2, iso_a3, created_at, updated_at) VALUES
  ('France', '-99', '-99', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('Kosovo', '-99', '-99', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('Norway', 'NO', 'NOR', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('Siachen Glacier', '-99', '-99', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
