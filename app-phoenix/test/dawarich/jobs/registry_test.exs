defmodule Dawarich.Jobs.RegistryTest do
  use ExUnit.Case, async: true

  alias Dawarich.Jobs.Registry

  test "registry keys are unique and existing native crons map to 23 unique Rails keys" do
    entries = Registry.entries()
    keys = Enum.map(entries, & &1.key)
    assert length(keys) == length(Enum.uniq(keys))
    crons = Enum.filter(entries, &(&1.kind == :cron and &1.key != "cron:cache_preheating_job"))
    assert length(crons) == 23
    assert Enum.count(entries, &(&1.kind == :cron and &1.key == "cron:cache_preheating_job")) == 1
    schedule = File.read!(Path.expand("../../../../config/schedule.yml", __DIR__))

    for %{key: "cron:" <> name, expression: expression} <- crons do
      assert [_, ^expression] = Regex.run(~r/^#{name}:\n\s+cron: "([^"]+)"/m, schedule)
    end

    for {key, worker} <- [
          {"cron:trek_sync_job", Dawarich.Integrations.TrekSchedulingWorker},
          {"cron:teslamate_sync_job", Dawarich.Integrations.TeslaMateSchedulingWorker}
        ] do
      assert [%{worker: ^worker}] = Enum.filter(entries, &(&1.key == key))
    end

    assert Registry.claimable() == []
  end

  test "cache entries remain unclaimable and only preheating has a cron" do
    entries = Enum.filter(Registry.entries(), &String.contains?(&1.key, "cache"))
    assert length(entries) == 2

    assert %{kind: :command, worker: Dawarich.Cache.PreheatUserWorker, claimable: false} =
             Enum.find(entries, &(&1.key == "command:cache.preheat_user"))

    assert %{
             kind: :cron,
             worker: Dawarich.Cache.PreheatSweepWorker,
             claimable: false,
             expression: "0 0 * * *",
             catch_up: false
           } =
             Enum.find(entries, &(&1.key == "cron:cache_preheating_job"))

    assert Registry.command("cache.preheat_user") == {:ok, Dawarich.Cache.PreheatUserWorker}
    assert Registry.command("cache.preheat_sweep") == :error
    assert Registry.claimable() == []
  end

  test "retention registry preserves cron expression and rollback claimability" do
    assert %{
             kind: :cron,
             expression: "45 3 * * *",
             claimable: false,
             worker: Dawarich.RouteVideos.PurgeWorker
           } =
             Enum.find(Registry.entries(), &(&1.key == "cron:route_videos_purge_job"))

    assert {"45 3 * * *", Dawarich.RouteVideos.PurgeWorker} in Registry.crontab()
  end

  test "release N claims nothing: every entry ships unclaimable" do
    assert Registry.claimable() == []
  end

  test "every key is namespaced, every cron entry has an expression and every worker exists" do
    for entry <- Registry.entries() do
      assert entry.key =~ ~r/\A(cron|command):[a-z0-9_.]+\z/
      assert Code.ensure_loaded?(entry.worker)
      if entry.kind == :cron, do: assert(is_binary(entry.expression))

      if entry.kind == :command,
        do: assert(function_exported?(entry.worker, :args_from_command, 2))
    end
  end

  test "catch_up is a boolean and appears only on cron entries" do
    for e <- Registry.entries(),
        Map.has_key?(e, :catch_up),
        do: assert(e.kind == :cron and is_boolean(e.catch_up))
  end

  test "registry lists the seven wave-2 commands and the Lite cron, all unclaimable" do
    wave2 = %{
      "command:exports.points" => Dawarich.Exports.PointsWorker,
      "command:mail.family_invitation" => Dawarich.Mail.FamilyInvitationWorker,
      "command:mail.family_lapse" => Dawarich.Mail.FamilyLapseWorker,
      "command:mail.user.welcome" => Dawarich.Mail.WelcomeWorker,
      "command:mail.user.archival_approaching" => Dawarich.Mail.ArchivalApproachingWorker,
      "command:mail.user.oauth_account_link" => Dawarich.Mail.OauthAccountLinkWorker,
      "command:mail.user.account_destroy_confirmation" =>
        Dawarich.Mail.AccountDestroyConfirmationWorker,
      "cron:lite_archival_warning_job" => Dawarich.Lite.ArchivalWarningWorker
    }

    entries = Map.new(Registry.entries(), &{&1.key, &1})

    for {"command:" <> _ = key, worker} <- wave2 do
      assert %{kind: :command, worker: ^worker, claimable: false} = entries[key], key
    end

    assert %{kind: :cron, worker: Dawarich.Lite.ArchivalWarningWorker, claimable: false} =
             entries["cron:lite_archival_warning_job"]

    assert Dawarich.Lite.ArchivalWarningWorker.key() == "cron:lite_archival_warning_job"
  end

  test "the wave-3 command keys are exactly these and unclaimable" do
    entries =
      for %{key: "command:" <> type} = entry <- Registry.entries(),
          type in ~w(achievements.check areas.relabel_visits),
          do: entry

    assert length(entries) == 2
    assert Enum.all?(entries, &(&1.claimable == false))
    assert Registry.command("achievements.check") == {:ok, Dawarich.Achievements.CheckWorker}
    assert Registry.command("areas.relabel_visits") == {:ok, Dawarich.Areas.RelabelWorker}
  end

  test "commands resolve by type and unknown types do not" do
    for %{kind: :command, key: "command:" <> type, worker: worker} <- Registry.entries() do
      assert Registry.command(type) == {:ok, worker}
    end

    assert Registry.command("nope") == :error
  end

  test "wave-5 keys are exact and unclaimable" do
    wave5 = %{
      "command:tracks.generate_range" => Dawarich.Tracks.RangeWorker,
      "command:tracks.generate_realtime" => Dawarich.Tracks.RealtimeWorker,
      "command:tracks.recalculate" => Dawarich.Tracks.RecalculateWorker,
      "command:transportation.reclassify_track" => Dawarich.Transportation.ReclassifyTrackWorker,
      "cron:daily_track_generation_job" => Dawarich.Tracks.DailyWorker
    }

    entries = Map.new(Registry.entries(), &{&1.key, &1})

    for {key, worker} <- wave5 do
      assert %{worker: ^worker, claimable: false} = entries[key], key
    end

    assert Registry.claimable() == []

    schedule = File.read!(Path.expand("../../../../config/schedule.yml", __DIR__))

    [_, expression] =
      Regex.run(~r/daily_track_generation_job:\n\s+cron: "([^"]+)"/, schedule)

    assert {expression, Dawarich.Tracks.DailyWorker} in Registry.crontab()
  end

  test "wave-5b commands resolve to their workers" do
    wave5b = %{
      "geocoding.reverse_point" => Dawarich.Geocoding.ReversePointWorker,
      "geocoding.reverse_place" => Dawarich.Geocoding.ReversePlaceWorker,
      "visits.suggest" => Dawarich.Visits.SuggestWorker,
      "visits.full_history_redetect" => Dawarich.Visits.RedetectWorker,
      "enhanced_import.extract_gpx" => Dawarich.EnhancedImport.ExtractGpxWorker,
      "enhanced_import.destroy_gpx" => Dawarich.EnhancedImport.DestroyGpxWorker
    }

    entries = Map.new(Registry.entries(), &{&1.key, &1})

    for {type, worker} <- wave5b do
      assert %{kind: :command, worker: ^worker, claimable: false} = entries["command:" <> type],
             type

      assert Registry.command(type) == {:ok, worker}
    end

    assert Registry.claimable() == []
  end

  @wave6_commands %{
    "release.point_dimensions_country" => Dawarich.ReleaseOperations.PointBackfill,
    "release.route_opacity" => Dawarich.ReleaseOperations.RouteOpacity,
    "release.onboarding_completed" => Dawarich.ReleaseOperations.OnboardingCompleted,
    "release.orphaned_tracks" => Dawarich.ReleaseOperations.OrphanedTracks,
    "release.tracks_dedup" => Dawarich.ReleaseOperations.TracksDedup,
    "release.place_name_locks" => Dawarich.ReleaseOperations.PlaceNameLocks,
    "release.time_anchor" => Dawarich.ReleaseOperations.TimeAnchor,
    "release.transportation" => Dawarich.ReleaseOperations.Transportation,
    "release.visits_fleet_redetect" => Dawarich.ReleaseOperations.VisitsFleetRedetect,
    "release.null_island" => Dawarich.ReleaseOperations.NullIsland,
    "release.motion_data" => Dawarich.ReleaseOperations.MotionData,
    "release.altitude" => Dawarich.ReleaseOperations.Altitude
  }

  @wave6_crons %{
    "cron:raw_data_archive_job" => Dawarich.RawData.ArchiveWorker,
    "cron:raw_data_verify_job" => Dawarich.RawData.VerifyWorker,
    "cron:raw_data_clear_job" => Dawarich.RawData.ClearWorker
  }

  test "wave-6 keys are exact and unclaimable; the raw-data crons match config/schedule.yml" do
    entries = Map.new(Registry.entries(), &{&1.key, &1})

    for {type, worker} <- @wave6_commands do
      assert %{kind: :command, worker: ^worker, claimable: false} = entries["command:" <> type],
             type

      assert Registry.command(type) == {:ok, worker}
    end

    assert Enum.count(Registry.entries(), &String.starts_with?(&1.key, "command:release.")) ==
             map_size(@wave6_commands) + 5

    schedule = File.read!(Path.expand("../../../../config/schedule.yml", __DIR__))

    for {"cron:" <> name = key, worker} <- @wave6_crons do
      assert %{kind: :cron, worker: ^worker, claimable: false, expression: expression} =
               entries[key],
             key

      assert worker.key() == key
      assert [_, ^expression] = Regex.run(~r/#{name}:\n\s+cron: "([^"]+)"/, schedule), key
      assert {expression, worker} in Registry.crontab()
    end

    assert Enum.count(Registry.entries(), &String.starts_with?(&1.key, "cron:raw_data_")) ==
             map_size(@wave6_crons)

    assert Registry.claimable() == []
  end

  test "seasonal raw-data crons opt out of catch-up" do
    entries = Map.new(Registry.entries(), &{&1.key, &1})

    assert %{catch_up: false} = entries["cron:raw_data_archive_job"]
    assert %{catch_up: false} = entries["cron:raw_data_clear_job"]
    assert entries["cron:raw_data_verify_job"].catch_up == false
  end

  test "the app-version cron has one source: the registry matches config/schedule.yml" do
    schedule = File.read!(Path.expand("../../../../config/schedule.yml", __DIR__))
    [_, expression] = Regex.run(~r/app_version_checking_job:\n\s+cron: "([^"]+)"/, schedule)

    assert {expression, Dawarich.AppVersion.CheckWorker} in Registry.crontab()
  end
end
