defmodule Dawarich.ReleaseMigrations.V1_3_4 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.3.4"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260313134546", &create_family_location_requests/1},
      {"20260314000001", &fix_route_opacity_default/1},
      {"20260315000001", &backfill_onboarding_completed_for_existing_users/1}
    ]
  end

  defp create_family_location_requests(repo) do
    sql!(repo, ~S"""
    CREATE TABLE "family_location_requests" ("id" bigserial primary key, "requester_id" bigint NOT NULL, "target_user_id" bigint NOT NULL, "family_id" bigint NOT NULL, "status" integer DEFAULT 0 NOT NULL, "suggested_duration" character varying DEFAULT '24h' NOT NULL, "expires_at" timestamp(6) NOT NULL, "responded_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
    CREATE INDEX "idx_family_loc_requests_requester_target_status" ON "family_location_requests" ("requester_id", "target_user_id", "status");
    CREATE INDEX "idx_family_loc_requests_target_status" ON "family_location_requests" ("target_user_id", "status");
    CREATE INDEX "idx_family_loc_requests_expires_status" ON "family_location_requests" ("expires_at", "status");
    CREATE INDEX "index_family_location_requests_on_family_id" ON "family_location_requests" ("family_id");
    ALTER TABLE "family_location_requests" ADD CONSTRAINT "fk_rails_f607841cdd"
    FOREIGN KEY ("requester_id")
      REFERENCES "users" ("id");
    ALTER TABLE "family_location_requests" ADD CONSTRAINT "fk_rails_d78ba34bd1"
    FOREIGN KEY ("target_user_id")
      REFERENCES "users" ("id");
    ALTER TABLE "family_location_requests" ADD CONSTRAINT "fk_rails_a52bcdbc28"
    FOREIGN KEY ("family_id")
      REFERENCES "families" ("id");
    """)
  end

  defp fix_route_opacity_default(_repo),
    do: {:jobs, [job("DataMigrations::FixRouteOpacityJob")]}

  defp backfill_onboarding_completed_for_existing_users(_repo),
    do: {:jobs, [job("DataMigrations::BackfillOnboardingCompletedJob")]}
end
