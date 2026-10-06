defmodule Dawarich.A12f3bH02Test do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.{Dispatch, Ownership, Registry}
  @oban __MODULE__.Oban
  @native [
    {~w(points.tile_epoch), Dawarich.Points.TileEpochWorker, "points.tile_epoch"},
    {~w(points.live_broadcast), Dawarich.Points.LiveBroadcastWorker, "points.live_broadcast"},
    {~w(points.anomaly_filter), Dawarich.Points.AnomalyArrivalWorker, "points.anomaly_filter"},
    {~w(points.anomaly_stats), Dawarich.Points.AnomalyStatsWorker, nil},
    {~w(points.anomaly_recalculate), Dawarich.Points.AnomalyFilter.RecalculateWorker,
     "points.anomaly_recalculate"},
    {~w(points.anomaly_backfill), Dawarich.Points.AnomalyBackfillWorker,
     "points.anomaly_backfill"},
    {~w(points.web_destroy_follow_up), Dawarich.Points.DeletionEffects, nil},
    {~w(tracks.realtime), Dawarich.Points.RealtimeTracksWorker, nil},
    {~w(visits.realtime), Dawarich.Visits.SuggestWorker, "visits.suggest"},
    {~w(visit_months_changed), Dawarich.Points.VisitMonthsWorker, nil},
    {~w(enhanced_import_card), Dawarich.Points.ImportCardWorker, nil},
    {~w(schedule_untracked_tracks), Dawarich.Points.UntrackedTracksWorker, nil},
    {~w(tracks.backfill), Dawarich.Tracks.BackfillWorker, "tracks.backfill"},
    {~w(tracks_throttled_backfill), Dawarich.Tracks.ThrottledBackfillWorker,
     "tracks.throttled_backfill"},
    {~w(tracks_realtime_retrigger), Dawarich.Tracks.RealtimeWorker, "tracks.generate_realtime"},
    {~w(geocode_recent_points), Dawarich.Tracks.RecentGeocoding, nil},
    {~w(tracks_changed), Dawarich.Tracks.NativeChanges, nil},
    {~w(transport_progress), Dawarich.Transportation.ReclassifyTrackWorker,
     "transportation.reclassify_track"},
    {~w(stats.calculate_month), Dawarich.Stats.CalculateMonthWorker, "stats.calculate_month"},
    {~w(stats.full_recalculation), Dawarich.Stats.FullRecalculationWorker,
     "stats.full_recalculation"},
    {~w(stats.caches_invalidated), Dawarich.Stats.CacheInvalidation, nil},
    {~w(airtrail_stats), Dawarich.AirTrail.StatsFollowUp, nil},
    {~w(digests.calculate_month), Dawarich.Digests.MonthlyWorker, "digests.calculate_month"},
    {~w(digests.calculate_year), Dawarich.Digests.YearlyWorker, "digests.calculate_year"},
    {~w(digests.email_month), Dawarich.Mail.Digests.MonthlyWorker, "mail.digest.monthly"},
    {~w(digests.email_year), Dawarich.Mail.Digests.YearlyWorker, "mail.digest.yearly"},
    {~w(family_location_request_mail), Dawarich.Mail.LocationRequestWorker,
     "mail.family_location_request"},
    {~w(mail.family_lapse), Dawarich.Mail.FamilyLapseWorker, "mail.family_lapse"},
    {~w(imports.upload_created), Dawarich.Imports.UploadRecords, nil},
    {~w(imports.progress imports.destroy_status imports.destroy_complete),
     Dawarich.Imports.Events, nil},
    {~w(imports.extraction_requested), Dawarich.EnhancedImport.ExtractGpxWorker,
     "enhanced_import.extract_gpx"},
    {~w(imports.extraction_destroy_requested), Dawarich.Imports.ExtractionRemovalWorker, nil},
    {~w(imports.postprocessing_step), Dawarich.Imports.Postprocessing.Native, nil},
    {~w(imports.destroy_requested), Dawarich.Imports.DestroyWorker, "imports.destroy"},
    {~w(imports.destroy_callbacks imports.destroy_stats), Dawarich.Imports.DestroyNativeEffects,
     nil},
    {~w(imports.destroy_achievements), Dawarich.Imports.ImportsDestroyAchievementsEffects, nil},
    {~w(imports.prepare_download), Dawarich.Imports.PrepareDownloadWorker,
     "imports.prepare_download"},
    {~w(imports.prepared_download_purge), Dawarich.Imports.ImportBlobPurgeWorker,
     "imports.prepared_download_purge"},
    {~w(posters.created), Dawarich.Posters.CreateWorker, "posters.create"},
    {~w(posters.progress), Dawarich.Posters.ProgressWorker, nil},
    {~w(posters.purge exports.purge), Dawarich.Exports.PurgeWorker, nil},
    {~w(route_videos.attachment_job), Dawarich.RouteVideos.AttachmentJob, nil},
    {~w(share_management.live_revoked), Dawarich.ShareManagement.Mutations, nil},
    {~w(visits.suggest), Dawarich.Visits.SuggestWorker, "visits.suggest"},
    {~w(visits.web_redetect), Dawarich.Visits.RedetectWorker, "visits.full_history_redetect"},
    {~w(achievements.check), Dawarich.Achievements.CheckWorker, "achievements.check"}
  ]
  @inline_callbacks %{
    Dawarich.Points.DeletionEffects => {:publish, 4},
    Dawarich.Tracks.RecentGeocoding => {:run, 4},
    Dawarich.Tracks.NativeChanges => {:write!, 2},
    Dawarich.Stats.CacheInvalidation => {:call, 2},
    Dawarich.AirTrail.StatsFollowUp => {:call, 2},
    Dawarich.Imports.UploadRecords => {:insert!, 4},
    Dawarich.Imports.Events => {:broadcast, 1},
    Dawarich.Imports.Postprocessing.Native => {:run!, 5},
    Dawarich.Imports.DestroyNativeEffects => {:run!, 6},
    Dawarich.Imports.ImportsDestroyAchievementsEffects => {:enqueue!, 4},
    Dawarich.RouteVideos.AttachmentJob => {:enqueue!, 2},
    Dawarich.ShareManagement.Mutations => {:run, 6}
  }
  @known_gaps ~w(
    achievements.bulk_check_leaf
    cache.preheat_sweep
    cache.preheat_user
    exports.points_created
    geocoding.reverse_point
    imports.destroy_terminal
    imports.normal_resume
    imports.resume
    integrations.airtrail_flights
    integrations.teslamate_sync
    integrations.trek_sync
    place_name_fetch
    places_bulk_name_fetch
    places_delete_if_orphan
    places_orphan_cleanup
    reverse_geocode_place
    release.anomalies
    release.anomalies_user
    release.per_tracker
    release_achievements_bulk_check
    release_null_island_follow_up
    release_reclassify_tracks
    release_user_redetect
    tracks_generate_range
    trips.calculate
    users.export_data
    users.import_data
    users.recalculate_data
  )

  setup do
    start_oban(@oban)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    previous = Map.take(System.get_env(), ~w(DAWARICH_RAILS SMTP_FROM DOMAIN RAILS_ENV))

    System.put_env(%{
      "DAWARICH_RAILS" => "off",
      "DOMAIN" => "www.example.com",
      "SMTP_FROM" => "h02@dawarich.test",
      "RAILS_ENV" => "staging"
    })

    on_exit(fn ->
      Enum.each(~w(DAWARICH_RAILS SMTP_FROM DOMAIN RAILS_ENV), &System.delete_env/1)
      System.put_env(previous)
    end)

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    :ok
  end

  @tag a12f3b_case: "H02a"
  test "standalone enumerates every reverse kind as native consumption or an explicit gap" do
    entries = Dawarich.Standalone.job_entries()
    keys = Enum.map(entries, & &1.key)
    assert length(keys) == length(Enum.uniq(keys))
    assert Registry.claimable() == []
    kinds = Enum.flat_map(@native, fn {kinds, _, _} -> kinds end) ++ @known_gaps
    assert length(kinds) == length(Enum.uniq(kinds))
    assert Enum.sort(kinds) == Enum.sort(Dawarich.RailsCommands.closure_kinds())

    for {kinds, consumer, command} <- @native do
      assert Code.ensure_loaded?(consumer), "missing native consumer for #{inspect(kinds)}"

      if command do
        assert {:ok, ^consumer} = Registry.command(command)
        assert Enum.any?(entries, &(&1.key == "command:" <> command and &1.worker == consumer))
      end

      if not function_exported?(consumer, :new, 1) do
        {callback, arity} = Map.fetch!(@inline_callbacks, consumer)
        assert function_exported?(consumer, callback, arity)
      end

      if function_exported?(consumer, :new, 1) do
        assert function_exported?(consumer, :perform, 1)
        runtime = File.read!(Path.expand("../../config/runtime.exs", __DIR__))
        assert String.contains?(runtime, to_string(consumer.__opts__()[:queue]) <> ":")
      end
    end

    report =
      File.read!(
        Path.expand("../../../docs/phoenix/standalone-reverse-gaps-after-h02.md", __DIR__)
      )

    documented = Regex.scan(~r/^\| `([^`]+)` \|/m, report) |> Enum.map(fn [_, kind] -> kind end)
    assert Enum.sort(documented) == Enum.sort(@known_gaps)

    for {type, payload} <- [
          {"points.tile_epoch", %{"user_id" => 1, "timestamps" => []}},
          {"points.live_broadcast",
           %{
             "user_id" => 1,
             "upserted" => [],
             "payloads" => [],
             "broadcast_id" => Ecto.UUID.generate()
           }},
          {"points.anomaly_filter",
           %{"user_id" => 1, "start_at" => 100, "end_at" => 200, "time_zone" => "Etc/UTC"}}
        ] do
      outbox!(command_type: type, payload: payload)
    end

    assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{dispatched: 3}
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    System.delete_env("DAWARICH_RAILS")
    assert Dawarich.Standalone.job_entries(%{}) == Registry.claimable()
  end

  @tag a12f3b_case: "H02mail"
  test "standalone residual family mail reaches native delivery under source pins and preserves coexistence" do
    for type <- ~w(mail.family_location_request mail.family_lapse) do
      reset!(ScratchRepo)
      load_family!()
      Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq, pinned: true)
      System.put_env("DAWARICH_RAILS", "off")

      payload =
        if type == "mail.family_location_request",
          do: %{"user_id" => 701, "request_id" => 704},
          else: %{"user_id" => 702, "family_id" => 703, "locale" => "en", "lapse_at" => "none"}

      for _ <- 1..2, do: publish_mail(type, payload)
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{dispatched: 1}
      assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{}
      assert [[args]] = rows("SELECT args FROM oban.oban_jobs")
      assert {:ok, worker} = Registry.command(type)

      assert worker.perform(%Oban.Job{
               args: args,
               conf: Oban.config(@oban),
               attempt: 1,
               max_attempts: 4
             }) == :ok

      assert_received {:mail, %{to: "target@dawarich.test"}}

      assert worker.perform(%Oban.Job{
               args: args,
               conf: Oban.config(@oban),
               attempt: 1,
               max_attempts: 4
             }) == :ok

      refute_received {:mail, _}

      assert rows("SELECT owner,pinned FROM phoenix.job_owners WHERE key=$1", ["command:" <> type]) ==
               [["sidekiq", true]]

      rows("DELETE FROM public.job_outbox")
      System.delete_env("DAWARICH_RAILS")
      publish_mail(type, payload)
      reverse = if type == "mail.family_lapse", do: type, else: "family_location_request_mail"
      assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [[reverse, payload]]
      assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]
    end
  end

  @tag a12f3b_case: "H02points"
  test "standalone point edit followups use native consumers while coexistence retains source payloads" do
    for type <- ~w(geocoding.reverse_point tracks.recalculate) do
      reset!(ScratchRepo)
      Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq, pinned: true)

      payload =
        if type == "tracks.recalculate",
          do: %{"track_id" => 705},
          else: %{"user_id" => 701, "point_ids" => [706], "force" => true}

      Dawarich.Points.ApiWrites.produce(ScratchRepo, type, payload, 701)
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{dispatched: 1}
      assert [[args]] = rows("SELECT args FROM oban.oban_jobs")
      assert {:ok, worker} = Registry.command(type)

      assert worker.perform(%Oban.Job{
               args: args,
               conf: Oban.config(@oban),
               attempt: 1,
               max_attempts: 4
             }) == :ok
    end

    reset!(ScratchRepo)
    Dawarich.StatsFixtures.reset!()
    Dawarich.StatsFixtures.user!(711, %{"timezone" => "Etc/UTC"})
    Dawarich.StatsFixtures.point!(7111, 711, 1_710_000_000)

    for type <- ~w(points.tile_epoch achievements.check stats.calculate_month),
        do: Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq, pinned: true)

    user = %{id: 711, status: 1, plan: 1, active_until: nil, settings: %{"timezone" => "Etc/UTC"}}
    ctx = %{self_hosted?: true, now: DateTime.utc_now()}

    for mode <- [:standalone, :coexistence] do
      if mode == :standalone,
        do: System.put_env("DAWARICH_RAILS", "off"),
        else: System.delete_env("DAWARICH_RAILS")

      rows("UPDATE points SET lock_version=0 WHERE id=7111")
      params = %{"point" => %{"latitude" => 52, "longitude" => 13}}

      assert {:ok, 200, _} =
               Dawarich.Points.ApiWrites.update(ScratchRepo, user, 7111, params, ctx)

      params = %{
        "point" => %{"latitude" => 53, "longitude" => 14, "revision" => 1},
        "history_scope" => %{"start_at" => "1", "end_at" => "2147483647"}
      }

      assert {:ok, 200, _} =
               Dawarich.Points.ApiPosition.update(ScratchRepo, user, 7111, params, ctx)

      if mode == :standalone do
        assert rows(
                 "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker' ORDER BY id"
               ) ==
                 [
                   [%{"user_id" => 711, "notify" => true, "oldest_timestamp" => 1_710_000_000}],
                   [%{"user_id" => 711, "notify" => true, "oldest_timestamp" => 1_710_000_000}]
                 ]

        assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      else
        assert rows(
                 "SELECT payload FROM phoenix.rails_commands WHERE kind='achievements.check' ORDER BY id"
               ) ==
                 [
                   [%{"user_id" => 711, "oldest_timestamp" => 1_710_000_000}],
                   [%{"user_id" => 711, "oldest_timestamp" => 1_710_000_000}]
                 ]
      end

      rows("DELETE FROM oban.oban_jobs")
      rows("DELETE FROM phoenix.rails_commands")
    end

    System.put_env("DAWARICH_RAILS", "off")
    reset!(ScratchRepo)
    Ownership.put!(ScratchRepo, "command:achievements.check", :sidekiq, pinned: true)
    payload = %{"user_id" => 701, "oldest_timestamp" => 100}
    assert Dawarich.Points.NativeEffects.achievements(ScratchRepo, payload) == :ok
    assert [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args == Map.put(payload, "notify", true)
    assert Dawarich.Achievements.CheckWorker.perform(%Oban.Job{args: args}) == :ok
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    System.delete_env("DAWARICH_RAILS")
    assert Dawarich.Points.NativeEffects.achievements(ScratchRepo, payload) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["achievements.check", payload]
           ]

    rows("DELETE FROM phoenix.rails_commands")
    payload = %{"user_id" => 701, "point_ids" => [706], "force" => true}
    Dawarich.Points.ApiWrites.produce(ScratchRepo, "geocoding.reverse_point", payload, 701)

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["geocoding.reverse_point", payload]
           ]
  end

  defp publish_mail("mail.family_location_request", payload),
    do: Dawarich.Mail.ResidualCommands.location(ScratchRepo, payload)

  defp publish_mail("mail.family_lapse", payload),
    do: Dawarich.Families.LapseNotices.publish(ScratchRepo, :sidekiq, payload, DateTime.utc_now())

  defp load_family! do
    for {id, email} <- [{701, "requester@dawarich.test"}, {702, "target@dawarich.test"}] do
      Dawarich.DigestFixtures.row!(ScratchRepo, "users", %{
        "id" => id,
        "email" => email,
        "settings" => %{"locale" => "en"},
        "created_at" => ~N[2026-10-04 12:00:00],
        "updated_at" => ~N[2026-10-04 12:00:00]
      })
    end

    rows(
      "INSERT INTO families(id,name,creator_id,created_at,updated_at) VALUES(703,'Synthetic family',701,now(),now())"
    )

    rows(
      "INSERT INTO family_location_requests(id,requester_id,target_user_id,family_id,status,suggested_duration,expires_at,created_at,updated_at) VALUES(704,701,702,703,0,'24h',now()+interval '1 day',now(),now())"
    )
  end
end
