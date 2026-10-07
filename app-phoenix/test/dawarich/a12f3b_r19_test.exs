defmodule Dawarich.A12f3bR19Test do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Ownership, Registry}
  alias Dawarich.ReleaseOperations.NullIsland
  alias Dawarich.Wave6Fixtures

  defmodule FailingRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo
    defdelegate query!(sql, params, opts), to: Dawarich.ScratchRepo

    def insert!(
          %Ecto.Changeset{changes: %{worker: "Dawarich.Stats.CalculateMonthWorker"}},
          _opts
        ),
        do: raise(ArgumentError, "follow-up unavailable")

    defdelegate insert!(changeset, opts), to: Dawarich.ScratchRepo
  end

  setup do
    saved = Map.new(~w(DAWARICH_RAILS TIME_ZONE), &{&1, System.get_env(&1)})
    System.put_env("TIME_ZONE", "Pacific/Honolulu")
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    on_exit(fn ->
      for {key, value} <- saved do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  @tag a12f3b_case: "R19k04"
  test "release_null_island_follow_up native producer reaches its source terminal effect" do
    for {mode, owner} <- [{"on", :oban}, {"off", :oban}, {"off", :sidekiq}] do
      Dawarich.JobsCase.reset!(ScratchRepo)
      System.put_env("DAWARICH_RAILS", mode)
      for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, owner)
      {user, track, island, visit, place, outside, foreign} = fixtures()

      assert NullIsland.flag(ScratchRepo, user) == :ok
      assert rows("SELECT anomaly FROM points WHERE id=$1", [island]) == [[true]]

      assert rows("SELECT anomaly FROM points WHERE id=ANY($1) ORDER BY id", [[outside, foreign]]) ==
               [[nil], [nil]]

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      assert rows("SELECT count(*) FROM visits WHERE id=$1", [visit]) == [[0]]
      assert rows("SELECT visit_id FROM points WHERE id=$1", [island]) == [[nil]]
      assert rows("SELECT count(*) FROM place_visits WHERE visit_id=$1", [visit]) == [[0]]

      assert rows(
               "SELECT count(*) FROM notes WHERE attachable_type='Visit' AND attachable_id=$1",
               [visit]
             ) == [[0]]

      jobs = rows("SELECT worker,args FROM oban.oban_jobs ORDER BY id")
      assert [stats] = for(["Dawarich.Stats.CalculateMonthWorker", args] <- jobs, do: args)

      assert stats == %{
               "user_id" => user,
               "year" => 2026,
               "month" => 2,
               "notify_on_failure" => true
             }

      assert [%{"track_id" => track}] ==
               for(["Dawarich.Tracks.RecalculateWorker", args] <- jobs, do: args)

      assert [tile] = for(["Dawarich.Points.TileEpochWorker", args] <- jobs, do: args)
      assert tile["user_id"] == user
      assert length(tile["timestamps"]) == 2

      for ["Dawarich.Points.TileEpochWorker", args] <- jobs,
          do: assert(Dawarich.Points.TileEpochWorker.perform(%Oban.Job{args: args}) == :ok)

      assert {:ok, token} =
               Dawarich.Redis.cache_command(["GET", "points:tile_epoch:#{user}:2026"])

      assert is_binary(token)

      assert Dawarich.Tracks.RecalculateWorker.run(ScratchRepo, nil, %{"track_id" => track}) ==
               :ok

      assert rows("SELECT ST_AsText(original_path) FROM tracks WHERE id=$1", [track]) == [
               ["LINESTRING(12.37 51.34,12.38 51.35)"]
             ]

      assert Dawarich.Stats.CalculateMonthWorker.perform(%Oban.Job{args: stats}) == :ok

      assert rows(
               "SELECT distance,calculation_version FROM stats WHERE user_id=$1 AND year=2026 AND month=2",
               [user]
             ) == [[0, 3]]

      assert rows(
               "SELECT command_type,payload FROM job_outbox WHERE command_type='places.delete_if_orphan'"
             ) ==
               [["places.delete_if_orphan", %{"user_id" => user, "place_id" => place}]]

      assert NullIsland.flag(ScratchRepo, user) == :ok

      assert rows(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker'"
             ) == [[2]]

      assert rows(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Tracks.RecalculateWorker'"
             ) == [[2]]

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    end

    Dawarich.JobsCase.reset!(ScratchRepo)
    System.put_env("DAWARICH_RAILS", "on")
    Ownership.put!(ScratchRepo, "command:release.null_island", :sidekiq)
    {user, _track, island, visit, _place, _outside, _foreign} = fixtures()
    assert NullIsland.flag(ScratchRepo, user) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["release_null_island_follow_up", %{"user_id" => user}]
           ]

    assert rows("SELECT anomaly FROM points WHERE id=$1", [island]) == [[true]]
    assert rows("SELECT count(*) FROM visits WHERE id=$1", [visit]) == [[1]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]

    Dawarich.JobsCase.reset!(ScratchRepo)
    Ownership.put!(ScratchRepo, "command:release.null_island", :oban)
    Ownership.put!(ScratchRepo, "command:points.tile_epoch", :oban)
    user = Wave6Fixtures.user!()
    track = Wave6Fixtures.track!(user)

    Wave6Fixtures.point!(user, %{
      "lonlat" => {:point, 0.01, 0.01},
      "track_id" => track,
      "timestamp" => DateTime.to_unix(~U[2026-03-01 00:30:00Z])
    })

    assert NullIsland.flag(ScratchRepo, user) == :ok

    assert [
             ["points.anomaly_recalculate", track_payload],
             ["stats.calculate_month", stats_payload]
           ] =
             rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY kind")

    assert track_payload == %{"user_id" => user, "track_id" => track, "job_queue" => nil}

    assert Map.delete(stats_payload, "run_at") == %{
             "user_id" => user,
             "year" => 2026,
             "month" => 2,
             "notify_on_failure" => true
           }

    assert is_integer(stats_payload["run_at"])
    assert rows("SELECT worker FROM oban.oban_jobs") == [["Dawarich.Points.TileEpochWorker"]]

    Dawarich.JobsCase.reset!(ScratchRepo)
    System.put_env("DAWARICH_RAILS", "off")
    {user, _track, point, visit, _place, _outside, _foreign} = fixtures()

    assert_raise ArgumentError, "follow-up unavailable", fn ->
      NullIsland.flag(FailingRepo, user)
    end

    assert rows("SELECT anomaly FROM points WHERE id=$1", [point]) == [[nil]]
    assert rows("SELECT count(*) FROM visits WHERE id=$1", [visit]) == [[1]]
    assert rows("SELECT count(*) FROM place_visits WHERE visit_id=$1", [visit]) == [[1]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert NullIsland.flag(ScratchRepo, 0) == :ok
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [user])
    assert NullIsland.flag(ScratchRepo, user) == :ok
    assert rows("SELECT anomaly FROM points WHERE id=$1", [point]) == [[nil]]
    assert NullIsland.flag(ScratchRepo, Wave6Fixtures.user!()) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  defp fixtures do
    user = Wave6Fixtures.user!(%{"settings" => %{"timezone" => "Asia/Tokyo"}})
    track = Wave6Fixtures.track!(user)
    stamp = DateTime.to_unix(~U[2026-03-01 00:30:00Z])

    place =
      Wave6Fixtures.insert!("places", %{
        "user_id" => user,
        "name" => "Island",
        "latitude" => 0.01,
        "longitude" => 0.01,
        "source" => 0,
        "lonlat" => {:point, 0.01, 0.01},
        "created_at" => NaiveDateTime.utc_now(),
        "updated_at" => NaiveDateTime.utc_now()
      })

    visit =
      Wave6Fixtures.insert!("visits", %{
        "user_id" => user,
        "place_id" => place,
        "name" => "Island",
        "status" => 0,
        "started_at" => ~N[2026-03-01 00:30:00],
        "ended_at" => ~N[2026-03-01 01:30:00],
        "duration" => 60,
        "demo" => false,
        "created_at" => NaiveDateTime.utc_now(),
        "updated_at" => NaiveDateTime.utc_now()
      })

    island =
      Wave6Fixtures.point!(user, %{
        "lonlat" => {:point, 0.01, 0.01},
        "track_id" => track,
        "visit_id" => visit,
        "timestamp" => stamp
      })

    Wave6Fixtures.point!(user, %{
      "lonlat" => {:point, 0.02, 0.02},
      "track_id" => track,
      "timestamp" => stamp + 60
    })

    outside =
      Wave6Fixtures.point!(user, %{
        "lonlat" => {:point, 12.37, 51.34},
        "track_id" => track,
        "timestamp" => stamp + 86400
      })

    Wave6Fixtures.point!(user, %{
      "lonlat" => {:point, 12.38, 51.35},
      "track_id" => track,
      "timestamp" => stamp + 86460
    })

    foreign =
      Wave6Fixtures.point!(Wave6Fixtures.user!(), %{
        "lonlat" => {:point, 0.01, 0.01},
        "timestamp" => stamp
      })

    rows(
      "INSERT INTO place_visits(visit_id,place_id,created_at,updated_at) VALUES($1,$2,now(),now())",
      [visit, place]
    )

    rows(
      "INSERT INTO notes(user_id,attachable_type,attachable_id,body,created_at,updated_at) VALUES($2,'Visit',$1,'synthetic',now(),now())",
      [visit, user]
    )

    rows(
      "INSERT INTO stats(user_id,year,month,distance,created_at,updated_at) VALUES($1,2026,2,999,now(),now())",
      [user]
    )

    {user, track, island, visit, place, outside, foreign}
  end
end
