defmodule Dawarich.Jobs.ResidualEntriesTest do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.{Dispatch, Registry, ResidualEntries}
  alias Dawarich.RailsJobOwners
  @oban __MODULE__.Oban

  @commands %{
    "tracks.backfill" => Dawarich.Tracks.BackfillWorker,
    "tracks.throttled_backfill" => Dawarich.Tracks.ThrottledBackfillWorker,
    "families.auto_create" => Dawarich.Families.AutoCreateWorker,
    "families.member_sync" => Dawarich.Families.MemberSyncWorker,
    "places.delete_if_orphan" => Dawarich.Places.DeleteIfOrphanWorker,
    "places.orphan_cleanup" => Dawarich.Places.OrphanCleanupWorker,
    "places.name_fetch" => Dawarich.Places.NameFetchWorker,
    "places.bulk_name_fetch" => Dawarich.Places.BulkNameFetchWorker,
    "achievements.bulk_check" => Dawarich.Achievements.BulkCheckWorker
  }
  @crons %{
    "airtrail_flight_import_job" => {"0 2 * * *", Dawarich.AirTrail.SyncSchedulingWorker},
    "teslamate_sync_job" => {"30 2 * * *", Dawarich.Integrations.TeslaMateSchedulingWorker},
    "trek_sync_job" => {"0 */6 * * *", Dawarich.Integrations.TrekSchedulingWorker},
    "achievements_bulk_check_job" => {"30 1 * * *", Dawarich.Achievements.BulkCheckWorker}
  }
  @owners %{
    "Tracks::BackfillGenerationJob" => ["command:tracks.backfill"],
    "Tracks::ThrottledBackfillJob" => ["command:tracks.throttled_backfill"],
    "AirTrail::SyncSchedulingJob" => ["cron:airtrail_flight_import_job"],
    "TeslaMate::SyncSchedulingJob" => ["cron:teslamate_sync_job"],
    "Trek::SyncSchedulingJob" => ["cron:trek_sync_job"],
    "Families::AutoCreationJob" => ["command:families.auto_create"],
    "Families::MemberSyncJob" => ["command:families.member_sync"],
    "Places::DeleteIfOrphanJob" => ["command:places.delete_if_orphan"],
    "Places::OrphanCleanupJob" => ["command:places.orphan_cleanup"],
    "Places::NameFetchingJob" => ["command:places.name_fetch"],
    "Places::BulkNameFetchingJob" => ["command:places.bulk_name_fetch"],
    "Achievements::BulkCheckJob" => [
      "command:achievements.bulk_check",
      "cron:achievements_bulk_check_job"
    ]
  }

  test "all twelve classes map to exact default-off keys and four retained cron expressions" do
    entries = Map.new(ResidualEntries.entries(), &{&1.key, &1})
    assert map_size(entries) == 13

    for {type, worker} <- @commands do
      assert %{worker: ^worker, kind: :command, claimable: false} = entries["command:" <> type]
      assert Registry.command(type) == {:ok, worker}
    end

    for {key, {expression, worker}} <- @crons do
      assert %{worker: ^worker, kind: :cron, expression: ^expression, claimable: false} =
               entries["cron:" <> key]

      assert {expression, worker} in Registry.crontab()
    end

    for {class, keys} <- @owners, do: assert(RailsJobOwners.owners()[class] == {:oban, keys})

    for class <-
          ~w(BulkVisitsSuggestingJob PendingImports::CleanupJob EnqueueBackgroundJob DataMigrations::BackfillAchievementsJob),
        do: assert(RailsJobOwners.owners()[class] == {:slice, :a12d2})

    assert RailsJobOwners.owners()["TeslaMate::SyncJob"] ==
             {:oban, ["command:imports.teslamate_sync"]}

    assert RailsJobOwners.owners()["Trek::SyncJob"] == {:oban, ["command:imports.trek_sync"]}
    assert Registry.claimable() == []
  end

  test "wrong versions and fields quarantine before effects and each supported command rehomes" do
    start_oban(@oban)
    payloads = payloads()

    Enum.each(payloads, fn {type, payload} ->
      outbox!(command_type: type, payload: payload)
      outbox!(command_type: type, command_version: 2, payload: payload)
      outbox!(command_type: type, payload: Map.put(payload, "extra", 1))
    end)

    assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{dispatched: 9, quarantined: 18}

    assert rows(
             "SELECT error_code,count(*) FROM job_outbox WHERE state='quarantined' GROUP BY error_code ORDER BY error_code"
           ) == [["invalid_payload", 9], ["unsupported_version", 9]]

    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    for {type, payload} <- payloads, {field, value} <- payload do
      worker = @commands[type]

      assert worker.args_from_command(
               1,
               Map.put(payload, field, if(is_binary(value), do: 7, else: "wrong"))
             ) == {:error, "invalid_payload"}

      if is_integer(value),
        do:
          assert(
            worker.args_from_command(1, Map.put(payload, field, 9_223_372_036_854_775_808)) ==
              {:error, "invalid_payload"}
          )
    end
  end

  defp payloads do
    %{
      "tracks.backfill" => %{
        "user_id" => 7,
        "cycle_id" => Ecto.UUID.generate(),
        "time_zone" => "UTC"
      },
      "tracks.throttled_backfill" => %{
        "user_id" => 7,
        "walk_id" => Ecto.UUID.generate(),
        "cursor_timestamp" => nil,
        "time_zone" => "UTC"
      },
      "families.auto_create" => %{"user_id" => 7, "time_zone" => "UTC"},
      "families.member_sync" => %{"family_id" => 7, "locale" => "de", "time_zone" => "UTC"},
      "places.delete_if_orphan" => %{"user_id" => 7, "place_id" => 8},
      "places.orphan_cleanup" => %{"user_id" => 7},
      "places.name_fetch" => %{"user_id" => 7, "place_id" => 8},
      "places.bulk_name_fetch" => %{},
      "achievements.bulk_check" => %{"notify" => true, "force" => false, "stale_only" => false}
    }
  end
end
