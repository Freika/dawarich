defmodule Dawarich.A12f3bR03Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.RailsEffects
  @at DateTime.to_unix(~U[2026-01-01 00:00:00Z])

  setup do
    rails = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if rails,
        do: System.put_env("DAWARICH_RAILS", rails),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    :ok
  end

  @tag a12f3b_case: "R03k01"
  test "points.web_destroy_follow_up native producer reaches its source terminal effect" do
    user = user!(%{"timezone" => "Europe/Berlin"})
    foreign = user!()
    own = point!(user, @at, {13.4, 52.5})
    other = point!(foreign, @at, {13.4, 52.5})
    actor = %{id: user, settings: %{"timezone" => "Europe/Berlin"}}
    now = DateTime.utc_now()

    assert {:ok, %{deleted: [%{id: ^own}]}} =
             Dawarich.Points.WebDestroy.run(
               ScratchRepo,
               actor,
               [to_string(own), to_string(other)],
               %{locale: "en", now: now}
             )

    assert [[tile]] = jobs("Dawarich.Points.TileEpochWorker")
    assert [[stats]] = jobs("Dawarich.Points.AnomalyStatsWorker")
    assert stats["year"] == 2026 and stats["month"] == 1
    assert [[achievements]] = jobs("Dawarich.Achievements.CheckWorker")
    assert achievements["oldest_timestamp"] == @at

    assert [[due]] =
             rows(
               "SELECT scheduled_at FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker'"
             )

    assert NaiveDateTime.diff(due, DateTime.to_naive(now)) == 60
    assert :ok = Dawarich.Points.TileEpochWorker.run(ScratchRepo, tile)

    assert {:ok, %{deleted: []}} =
             Dawarich.Points.WebDestroy.run(ScratchRepo, actor, [to_string(own)], %{
               locale: "en",
               now: now
             })

    assert length(jobs("Dawarich.Achievements.CheckWorker")) == 1
    assert rows("SELECT id FROM points WHERE user_id=$1", [foreign]) == [[other]]
    assert reverse("points.web_destroy_follow_up") == []
    System.delete_env("DAWARICH_RAILS")
    another = point!(user, @at + 60, {13.4, 52.5})

    assert {:ok, _} =
             Dawarich.Points.WebDestroy.run(ScratchRepo, actor, [to_string(another)], %{
               locale: "en",
               now: now
             })

    assert length(reverse("points.web_destroy_follow_up")) == 1
  end

  @tag a12f3b_case: "R03k02"
  test "schedule_untracked_tracks native producer reaches its source terminal effect" do
    user = user!(%{"timezone" => "Pacific/Chatham"})
    import = import!(user)
    a = point!(user, @at, {13.4, 52.5})
    b = point!(user, @at + 60, {13.401, 52.5})
    rows("UPDATE points SET import_id=$1 WHERE id=ANY($2::bigint[])", [import, [a, b]])

    {:ok, :ok} =
      ScratchRepo.transaction(fn -> RailsEffects.untracked_tracks(ScratchRepo, user, import) end)

    assert [[args]] = jobs("Dawarich.Points.UntrackedTracksWorker")
    start_oban(:rx_untracked)
    assert :ok = Dawarich.Points.UntrackedTracksWorker.run(ScratchRepo, :rx_untracked, args)
    assert :ok = Dawarich.Points.UntrackedTracksWorker.run(ScratchRepo, :rx_untracked, args)

    assert rows(
             "SELECT user_id,import_id,untracked_only,total_chunks FROM phoenix.track_generations"
           ) == [[user, import, true, 1]]

    assert rows("SELECT start_ts,end_ts FROM phoenix.track_generation_chunks") == [
             [@at, @at + 60]
           ]

    assert reverse("schedule_untracked_tracks") == []

    coexist(
      "tracks.generate_range",
      fn -> RailsEffects.untracked_tracks(ScratchRepo, user, import) end,
      "schedule_untracked_tracks"
    )
  end

  @tag a12f3b_case: "R03k03"
  test "enhanced_import_card native producer reaches its source terminal effect" do
    user = user!()
    import = import!(user)
    :ok = Dawarich.Imports.Events.subscribe(user)
    RailsEffects.import_card(ScratchRepo, user, import)
    assert [[args]] = jobs("Dawarich.Points.ImportCardWorker")
    assert :ok = Dawarich.Points.ImportCardWorker.run(ScratchRepo, args)
    assert_receive :imports_changed
    assert reverse("enhanced_import_card") == []
    args = Map.put(args, "user_id", user!())
    assert :ok = Dawarich.Points.ImportCardWorker.run(ScratchRepo, args)
    refute_received :imports_changed

    coexist(
      "enhanced_import.extract_gpx",
      fn -> RailsEffects.import_card(ScratchRepo, user, import) end,
      "enhanced_import_card"
    )
  end

  @tag a12f3b_case: "R03k04"
  test "visit_months_changed native producer reaches its source terminal effect" do
    user = user!(%{"timezone" => "Pacific/Chatham"})

    [[area]] =
      rows(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Synthetic area',52.5,13.4,200,now(),now()) RETURNING id",
        [user]
      )

    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,created_at,updated_at) VALUES($1,'Synthetic place',52.5,13.4,now(),now()) RETURNING id",
        [user]
      )

    rows(
      "INSERT INTO visits(user_id,place_id,name,status,detection_version,duration,started_at,ended_at,created_at,updated_at) VALUES($1,$2,'Detected',0,1,60,'2025-12-31 23:59:00','2026-01-01 00:59:00',now(),now())",
      [user, place]
    )

    key = "timeline_month_summary/#{user}/2026-01/Pacific/Chatham/pro/v3"
    other = "timeline_month_summary/#{user}/2025-12/Pacific/Chatham/pro/v3"
    for k <- [key, other], do: Dawarich.Redis.cache_command(["SET", k, "stale"])
    assert :ok = Dawarich.Areas.relabel(ScratchRepo, area)
    assert [[args]] = jobs("Dawarich.Points.VisitMonthsWorker")
    assert :ok = Dawarich.Points.VisitMonthsWorker.run(ScratchRepo, args)
    assert {:ok, nil} = Dawarich.Redis.cache_command(["GET", key])
    assert {:ok, "stale"} = Dawarich.Redis.cache_command(["GET", other])

    assert rows("SELECT name,area_id FROM visits WHERE user_id=$1", [user]) == [
             ["Synthetic area", area]
           ]

    summary =
      Dawarich.Timeline.MonthSummary.build(
        %{id: user, settings: %{"timezone" => "Pacific/Chatham"}},
        "2026-01",
        nil,
        DateTime.utc_now(),
        ScratchRepo
      )

    assert Enum.any?(List.flatten(summary.weeks), &(Map.get(&1, :visit_count) == 1))
    assert reverse("visit_months_changed") == []

    coexist(
      "visits.suggest",
      fn -> RailsEffects.visit_months(ScratchRepo, user, [~U[2025-12-31 23:59:00Z]]) end,
      "visit_months_changed"
    )
  end

  defp import!(user) do
    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,created_at,updated_at) VALUES($1,'Synthetic import',0,now(),now()) RETURNING id",
        [user]
      )

    id
  end

  defp jobs(worker),
    do: rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 ORDER BY id", [worker])

  defp reverse(kind), do: rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1", [kind])

  defp coexist(key, fun, kind) do
    System.delete_env("DAWARICH_RAILS")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:" <> key, :sidekiq, pinned: true)
    fun.()
    assert length(reverse(kind)) == 1
  end
end
