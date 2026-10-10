defmodule Dawarich.ReleaseMigrations.V1_9_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.9.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260207075817", &create_notes_and_rename_trips_rich_text/1},
      {"20260208223255", &fix_countries_with_missing_iso_codes/1},
      {"20260521121115", &create_shared_links/1},
      {"20260529120000", &create_flights/1}
    ]
  end

  defp create_notes_and_rename_trips_rich_text(repo) do
    sql!(repo, ~S"""
    CREATE TABLE IF NOT EXISTS "notes" ("id" bigserial primary key, "user_id" bigint NOT NULL, "title" character varying, "body" text, "lonlat" geography(POINT,4326), "attachable_type" character varying, "attachable_id" bigint, "noted_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_7f2323ad43"
    FOREIGN KEY ("user_id")
      REFERENCES "users" ("id")
    );
    CREATE INDEX IF NOT EXISTS "index_notes_on_user_id" ON "notes" ("user_id");
    CREATE INDEX IF NOT EXISTS "index_notes_on_attachable_type_and_attachable_id" ON "notes" ("attachable_type", "attachable_id");
    CREATE INDEX IF NOT EXISTS "index_notes_on_lonlat" ON "notes" USING gist ("lonlat");
    CREATE INDEX IF NOT EXISTS "index_notes_on_user_id_and_noted_at" ON "notes" ("user_id", "noted_at");
    CREATE UNIQUE INDEX IF NOT EXISTS index_notes_on_attachable_and_noted_date ON notes (attachable_type, attachable_id, (CAST(noted_at AS date))) WHERE attachable_id IS NOT NULL;
    UPDATE action_text_rich_texts SET name = 'description' WHERE record_type = 'Trip' AND name = 'notes';
    """)
  end

  defp fix_countries_with_missing_iso_codes(repo) do
    sql!(repo, ~S"""
    UPDATE countries SET iso_a2 = 'FR', iso_a3 = 'FRA' WHERE name = 'France' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'NO', iso_a3 = 'NOR' WHERE name = 'Norway' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'XK', iso_a3 = 'XKX' WHERE name = 'Kosovo' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'SO', iso_a3 = 'SOM' WHERE name = 'Somaliland' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'CY', iso_a3 = 'CYP' WHERE name = 'Northern Cyprus' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'GB', iso_a3 = 'GBR' WHERE name = 'Dhekelia Sovereign Base Area' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'GB', iso_a3 = 'GBR' WHERE name = 'Akrotiri Sovereign Base Area' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'US', iso_a3 = 'USA' WHERE name = 'US Naval Base Guantanamo Bay' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'CY', iso_a3 = 'CYP' WHERE name = 'Cyprus No Mans Area' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'KZ', iso_a3 = 'KAZ' WHERE name = 'Baykonur Cosmodrome' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'BR', iso_a3 = 'BRA' WHERE name = 'Brazilian Island' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'AU', iso_a3 = 'AUS' WHERE name = 'Indian Ocean Territories' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'AU', iso_a3 = 'AUS' WHERE name = 'Coral Sea Islands' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'FR', iso_a3 = 'FRA' WHERE name = 'Clipperton Island' AND iso_a2 = '-99';
    UPDATE countries SET iso_a2 = 'AU', iso_a3 = 'AUS' WHERE name = 'Ashmore and Cartier Islands' AND iso_a2 = '-99';
    """)
  end

  defp create_shared_links(repo) do
    sql!(repo, ~S"""
    CREATE TABLE IF NOT EXISTS "shared_links" ("id" uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY, "user_id" bigint NOT NULL, "resource_type" integer NOT NULL, "resource_id" bigint, "name" character varying(255) NOT NULL, "magic_phrase" character varying(255), "expires_at" timestamp(6), "revoked_at" timestamp(6), "settings" jsonb DEFAULT '{}' NOT NULL, "view_count" integer DEFAULT 0 NOT NULL, "last_accessed_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_1b04e35c4c"
    FOREIGN KEY ("user_id")
      REFERENCES "users" ("id")
     ON DELETE CASCADE);
    CREATE INDEX IF NOT EXISTS "index_shared_links_on_user_id" ON "shared_links" ("user_id");
    CREATE INDEX IF NOT EXISTS "index_shared_links_on_resource_type_and_resource_id" ON "shared_links" ("resource_type", "resource_id") WHERE resource_id IS NOT NULL;
    CREATE INDEX IF NOT EXISTS "index_shared_links_active_by_user" ON "shared_links" ("user_id") WHERE revoked_at IS NULL;
    """)
  end

  defp create_flights(repo) do
    sql!(repo, ~S"""
    CREATE TABLE IF NOT EXISTS "flights" ("id" bigserial primary key, "user_id" bigint NOT NULL, "external_id" integer NOT NULL, "flight_date" date, "date_precision" character varying DEFAULT 'day' NOT NULL, "departure_time" timestamp(6), "arrival_time" timestamp(6), "from_code" character varying, "from_name" character varying, "from_lat" float, "from_lon" float, "to_code" character varying, "to_name" character varying, "to_lat" float, "to_lon" float, "airline_name" character varying, "airline_iata" character varying, "aircraft_name" character varying, "aircraft_reg" character varying, "flight_number" character varying, "seat" character varying, "seat_class" character varying, "note" text, "distance_km" float, "raw" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_f23525dbb0"
    FOREIGN KEY ("user_id")
      REFERENCES "users" ("id")
    );
    CREATE INDEX IF NOT EXISTS "index_flights_on_user_id" ON "flights" ("user_id");
    CREATE UNIQUE INDEX IF NOT EXISTS "index_flights_on_user_id_and_external_id" ON "flights" ("user_id", "external_id");
    CREATE INDEX IF NOT EXISTS "index_flights_on_user_id_and_departure_time" ON "flights" ("user_id", "departure_time");
    """)
  end
end
