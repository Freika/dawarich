defmodule Dawarich.ReleaseMigrations.V1_10_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.10.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260521121527", &create_pending_imports/1},
      {"20260611135333", &create_posters/1}
    ]
  end

  defp create_pending_imports(repo) do
    sql!(repo, ~S"""
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    CREATE TABLE "pending_imports" ("id" bigserial primary key, "claim_ticket" uuid DEFAULT gen_random_uuid() NOT NULL, "original_filename" character varying NOT NULL, "source_hint" character varying, "origin" character varying NOT NULL, "expires_at" timestamp(6) NOT NULL, "claimed_at" timestamp(6), "claimed_by_user_id" bigint, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
    CREATE UNIQUE INDEX "index_pending_imports_on_claim_ticket" ON "pending_imports" ("claim_ticket");
    CREATE INDEX "index_pending_imports_on_expires_at" ON "pending_imports" ("expires_at");
    CREATE INDEX "index_pending_imports_on_claimed_by_user_id" ON "pending_imports" ("claimed_by_user_id");
    ALTER TABLE "pending_imports" ADD CONSTRAINT "fk_rails_67c288c383"
    FOREIGN KEY ("claimed_by_user_id")
      REFERENCES "users" ("id")
     ON DELETE SET NULL;
    """)
  end

  defp create_posters(repo) do
    sql!(repo, ~S"""
    CREATE TABLE IF NOT EXISTS "posters" ("id" bigserial primary key, "user_id" bigint NOT NULL, "name" character varying NOT NULL, "status" integer DEFAULT 0 NOT NULL, "settings" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_f1941d801b"
    FOREIGN KEY ("user_id")
      REFERENCES "users" ("id")
    );
    CREATE INDEX IF NOT EXISTS "index_posters_on_user_id" ON "posters" ("user_id");
    """)
  end
end
