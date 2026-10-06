defmodule Dawarich.A12f3bR02Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.Points.{AnomalyFilter, AnomalyBackfillWorker}
  alias Dawarich.Ingest.Intake
  @at DateTime.to_unix(~U[2025-12-31 23:59:00Z])

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

  @tag a12f3b_case: "R02k01"
  test "points.anomaly_filter native producer reaches its source terminal effect" do
    user = user!(%{"timezone" => "Europe/Berlin"})
    payload = %{lonlat: "POINT(13.4 52.5)", timestamp: @at, accuracy: 20_000}
    [%{id: id}] = Intake.prepare([payload], user) |> Intake.write(user, repo: ScratchRepo)
    assert [[args]] = jobs("Dawarich.Points.AnomalyArrivalWorker")
    assert args["start_at"] == @at and args["end_at"] == @at
    assert args["time_zone"] == "Europe/Berlin"
    assert :ok = Dawarich.Points.AnomalyArrivalWorker.run(ScratchRepo, args)
    assert flagged(user) == [id]
    assert :ok = Dawarich.Points.AnomalyArrivalWorker.run(ScratchRepo, args)
    assert length(jobs("Dawarich.Points.AnomalyStatsWorker")) == 1
    assert reverse("points.anomaly_filter") == []

    Dawarich.Imports.Teslamate.Effects.finalize(
      %{
        repo: ScratchRepo,
        id: user,
        settings: %{"timezone" => "Europe/Berlin"},
        event: Ecto.UUID.generate(),
        now: DateTime.utc_now()
      },
      %{range: {@at, @at}, months: []}
    )

    assert length(jobs("Dawarich.Points.AnomalyArrivalWorker")) == 2
    assert reverse("points.anomaly_filter") == []

    coexist("points.anomaly_filter", fn ->
      Intake.prepare([payload], user) |> Intake.write(user, repo: ScratchRepo)
    end)
  end

  @tag a12f3b_case: "R02k02"
  test "points.anomaly_recalculate native producer reaches its source terminal effect" do
    user = user!()

    [[track]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,now(),now(),ST_GeomFromText('LINESTRING(13 52,14 53)',4326),now(),now()) RETURNING id",
        [user]
      )

    id = point!(user, @at, {13.4, 52.5}, accuracy: 20_000)
    rows("UPDATE points SET track_id=$1 WHERE id=$2", [track, id])

    assert AnomalyFilter.call(ScratchRepo, user, @at, @at, zone: "UTC", job_queue: :low_priority) ==
             1

    assert [[args]] = jobs("Dawarich.Points.AnomalyFilter.RecalculateWorker")
    assert args == %{"user_id" => user, "track_id" => track, "job_queue" => "low_priority"}

    assert rows(
             "SELECT queue FROM oban.oban_jobs WHERE worker='Dawarich.Points.AnomalyFilter.RecalculateWorker'"
           ) == [["low_priority"]]

    assert :ok = Dawarich.Points.AnomalyFilter.RecalculateWorker.run(ScratchRepo, args)
    assert rows("SELECT id FROM tracks WHERE id=$1", [track]) == []
    assert :ok = Dawarich.Points.AnomalyFilter.RecalculateWorker.run(ScratchRepo, args)
    assert reverse("points.anomaly_recalculate") == []
  end

  @tag a12f3b_case: "R02k03"
  test "points.anomaly_stats native producer reaches its source terminal effect" do
    user = user!(%{"timezone" => "Europe/Berlin"})
    point!(user, @at, {13.4, 52.5}, accuracy: 20_000)

    rows(
      "INSERT INTO stats(user_id,year,month,distance,sharing_uuid,created_at,updated_at) VALUES($1,2026,1,999,gen_random_uuid(),now(),now())",
      [user]
    )

    assert AnomalyFilter.call(ScratchRepo, user, @at, @at,
             zone: "Europe/Berlin",
             job_queue: :low_priority
           ) == 1

    assert [[args]] = jobs("Dawarich.Points.AnomalyStatsWorker")
    assert args["year"] == 2026 and args["month"] == 1

    assert rows(
             "SELECT queue FROM oban.oban_jobs WHERE worker='Dawarich.Points.AnomalyStatsWorker'"
           ) == [["low_priority"]]

    key = "dawarich/user_#{user}_total_distance"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "stale"])
    assert :ok = Dawarich.Points.AnomalyStatsWorker.run(ScratchRepo, args)
    assert {:ok, nil} = Dawarich.Redis.cache_command(["GET", key])

    assert rows("SELECT distance FROM stats WHERE user_id=$1 AND year=2026 AND month=1", [user]) ==
             [[0]]

    assert reverse("points.anomaly_stats") == []
    assert AnomalyFilter.call(ScratchRepo, user, @at, @at, zone: "Europe/Berlin") == 0
    assert length(jobs("Dawarich.Points.AnomalyStatsWorker")) == 1
  end

  @tag a12f3b_case: "R02k04"
  test "points.anomaly_backfill native producer reaches its source terminal effect" do
    user = user!()
    point!(user, @at, {13.4, 52.5}, anomaly: true)

    payload = %{
      "user_id" => user,
      "reset" => true,
      "notify" => false,
      "rebuild" => "async",
      "source_job_id" => Ecto.UUID.generate(),
      "ambient_zone" => "UTC",
      "progress" => %{}
    }

    assert :ok = AnomalyBackfillWorker.enqueue(ScratchRepo, payload)
    assert [[args]] = jobs("Dawarich.Points.AnomalyBackfillWorker")
    assert args["event_id"] == payload["source_job_id"]
    assert {:ok, true} = AnomalyBackfillWorker.run(ScratchRepo, nil, args)
    assert {:ok, true} = AnomalyBackfillWorker.run(ScratchRepo, nil, args)
    assert [[rebuild]] = jobs("Dawarich.Users.RecalculateWorker")
    assert rebuild["event_id"] == AnomalyBackfillWorker.rebuild_id(args)
    assert rebuild["ambient_zone"] == "UTC"
    assert length(jobs("Dawarich.Achievements.CheckWorker")) == 1
    assert flagged(user) == []
    assert reverse("points.anomaly_backfill") == []

    assert rows("SELECT key FROM phoenix.cursors WHERE key=$1", [
             "anomaly_backfill:progress:" <> args["event_id"]
           ]) == []

    coexist("points.anomaly_backfill", fn ->
      AnomalyBackfillWorker.enqueue(ScratchRepo, payload)
    end)
  end

  defp jobs(worker),
    do: rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 ORDER BY id", [worker])

  defp reverse(kind), do: rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1", [kind])

  defp coexist(key, fun) do
    System.delete_env("DAWARICH_RAILS")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:" <> key, :sidekiq, pinned: true)
    fun.()
    assert length(reverse(key)) == 1
  end
end
