defmodule Dawarich.UserData.RestorePointsTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Restore.{Places, Visits, Imports, Points}

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    c = UserDataSeeds.seed!("v2", ScratchRepo)
    %{c: c}
  end

  @tag :restore_tile_retry
  test "restore cache outage retains durable invalidation through duplicate replay", %{c: c} do
    previous = System.get_env("DAWARICH_RAILS")
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    key = "points:tile_epoch:#{c.user_id}:2026"

    try do
      for {mode, owner, offset} <-
            Enum.filter([{"on", :oban, 0}, {"on", :sidekiq, 1}, {"off", :sidekiq, 2}], fn {mode,
                                                                                           _, _} ->
              System.get_env("DAWARICH_REDELIVERY_TEST_MODE", mode) == mode
            end) do
        System.put_env("DAWARICH_RAILS", mode)
        Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:points.tile_epoch", owner)
        rows("DELETE FROM oban.oban_jobs WHERE worker='Dawarich.Points.TileEpochWorker'")
        rows("DELETE FROM phoenix.rails_commands WHERE kind='points.tile_epoch'")
        assert {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", key, "synthetic-before"])
        stop_supervised(Dawarich.Redis.Cache)
        context = Map.put(c.context, :native_owner, true)
        data = [%{"timestamp" => 1_767_225_600 + offset, "longitude" => 12.4, "latitude" => 51.3}]
        assert Points.call(ScratchRepo, c.user_id, data, context) == 1
        assert Points.call(ScratchRepo, c.user_id, data, context) == 0

        payload =
          if mode == "on" and owner == :sidekiq do
            assert [[payload]] =
                     rows(
                       "SELECT payload FROM phoenix.rails_commands WHERE kind='points.tile_epoch'"
                     )

            payload
          else
            assert [[payload]] =
                     rows(
                       "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Points.TileEpochWorker'"
                     )

            payload
          end

        assert_raise MatchError, fn ->
          Dawarich.Points.TileEpochWorker.run(ScratchRepo, payload)
        end

        start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
        assert :ok = Dawarich.Points.TileEpochWorker.run(ScratchRepo, payload)
        assert {:ok, token} = Dawarich.Redis.cache_command(["GET", key])
        refute token == "synthetic-before"
      end
    after
      Dawarich.Redis.cache_command(["DEL", key])

      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end
  end

  @tag :tmp_dir
  test "restore points preserve references columns conflicts and 5000 boundary", %{
    c: c,
    tmp_dir: dir
  } do
    entries = UserDataSeeds.entries("export_UTC")
    decode = fn bytes -> bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1) end
    assert Places.call(ScratchRepo, c.user_id, decode.(entries["places.jsonl"]), c.context) == 1

    assert Visits.call(
             ScratchRepo,
             c.user_id,
             decode.(entries["visits/2026/2026-01.jsonl"]),
             c.context
           ) == 1

    assert Imports.call(ScratchRepo, c.user_id, decode.(entries["imports.jsonl"]), dir, c.context) ==
             [1, 0]

    rows(
      "INSERT INTO countries(id,name,iso_a2,iso_a3,created_at,updated_at) VALUES(988991,'Synthetic Republic','ZZ','ZZZ',$1,$1)",
      [c.context.now]
    )

    data =
      entries
      |> Enum.filter(fn {name, _} -> String.starts_with?(name, "points/") end)
      |> Enum.sort()
      |> Enum.flat_map(fn {_, bytes} -> decode.(bytes) end)

    assert Points.call(ScratchRepo, c.user_id, data, c.context) == 3
    assert Points.call(ScratchRepo, c.user_id, data, c.context) == 0

    assert [[3, 1, 1, 1, 1]] ==
             rows(
               "SELECT count(*),count(DISTINCT import_id),count(DISTINCT country_id),count(DISTINCT visit_id),count(DISTINCT source_id) FROM points"
             )

    [[digest]] = rows("SELECT digest FROM point_sources")
    assert digest == hd(c.expected["rows"]["points"])["source_id"]
    assert [[0, 0]] == rows("SELECT raw_points,doubles FROM imports")

    assert Enum.map(data, & &1["timestamp"]) |> Enum.sort() ==
             rows("SELECT timestamp FROM points ORDER BY timestamp") |> List.flatten()

    assert [[%{"flag" => false, "nullable" => nil}, %{}, ["home"], [], "12.00", "1.25"]] ==
             rows(
               "SELECT raw_data,geodata,inrids,in_regions,altitude_decimal::text,velocity FROM points LIMIT 1"
             )

    alternate =
      hd(data)
      |> Map.put("timestamp", 1_800_000_000)
      |> put_in(["import_reference", "source"], "owntracks")

    assert Points.call(ScratchRepo, c.user_id, [alternate], c.context) == 1
    assert [[true]] == rows("SELECT import_id IS NOT NULL FROM points WHERE timestamp=1800000000")
    rows("DELETE FROM points")
    rows("TRUNCATE phoenix.rails_commands RESTART IDENTITY")

    for n <- [4999, 5000, 5001] do
      source = Path.expand("../../fixtures/user_data/boundary_#{n}/entries/points.jsonl", __DIR__)
      stream = source |> File.stream!() |> Stream.map(&Jason.decode!/1)
      assert Points.call(ScratchRepo, c.user_id, stream, c.context) == n

      assert [[^n, 1_767_225_600, max, true, true]] =
               rows(
                 "SELECT count(*),min(timestamp),max(timestamp),bool_and(ST_AsText(lonlat::geometry)='POINT(12.4 51.3)'),bool_and(import_id IS NULL AND anomaly IS NULL) FROM points"
               )

      assert max == 1_767_225_600 + (n - 1) * 60
      expected = if n <= 5000, do: [n], else: [5000, 1]

      assert rows(
               "SELECT jsonb_array_length(payload->'timestamps') FROM phoenix.rails_commands WHERE kind='points.tile_epoch' ORDER BY id"
             )
             |> List.flatten() == expected

      assert Points.call(ScratchRepo, c.user_id, stream, c.context) == 0
      assert [[^n]] = rows("SELECT count(*) FROM points")
      assert [[0, 0]] == rows("SELECT raw_points,doubles FROM imports")
      rows("DELETE FROM points")
      rows("TRUNCATE phoenix.rails_commands RESTART IDENTITY")
    end

    assert [] == rows("SELECT command_type FROM job_outbox")
  end

  test "restore point batch failure preserves actual outer transaction outcome", %{c: c} do
    oracle =
      Path.expand("../../fixtures/user_data/points_sql_failure.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    bad = %{
      "timestamp" => 1_767_225_600,
      "lonlat" => "POINT(12.4 51.3)",
      "course" => "100000000000"
    }

    assert {:error, :rollback} =
             ScratchRepo.transaction(fn ->
               count = Points.call(ScratchRepo, c.user_id, [bad], c.context)
               {:error, e} = ScratchRepo.query("SELECT 1", [], log: false)

               Process.put(:sql_failure_state, %{
                 "inserted" => count,
                 "sqlstate" => e.postgres[:pg_code],
                 "points" => 0
               })
             end)

    assert Process.get(:sql_failure_state) == oracle
    assert [[0]] == rows("SELECT count(*) FROM points")
    assert Points.call(ScratchRepo, c.user_id, [bad], c.context) == 0
    valid = Map.delete(bad, "course")
    assert Points.call(ScratchRepo, c.user_id, [valid], c.context) == 1

    assert Points.call(
             ScratchRepo,
             c.user_id,
             [%{valid | "timestamp" => 2_147_483_648}],
             c.context
           ) == 0

    assert Points.call(ScratchRepo, c.user_id, [Map.put(valid, "geodata", nil)], c.context) == 0
    assert [[1]] == rows("SELECT count(*) FROM points")
  end

  test "restore points do not trust archived anomaly or foreign owner", %{c: c} do
    bytes = UserDataSeeds.entries("dropped_columns")["points.jsonl"]
    data = bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    data =
      Enum.map(
        data,
        &(Map.put(&1, "anomaly", true)
          |> Map.put("import_id", 123)
          |> Map.put("visit_id", 124)
          |> Map.put("track_id", 125))
      )

    assert Points.call(ScratchRepo, c.user_id, [nil, %{}, false] ++ data, c.context) == 1

    assert [[c.user_id, nil, nil, nil, nil, ["home"], %{"flag" => false}, "12.00"]] ==
             rows(
               "SELECT user_id,anomaly,import_id,visit_id,track_id,inrids,raw_data,altitude_decimal::text FROM points"
             )

    assert [[0]] == rows("SELECT count(*) FROM points WHERE user_id=988002")
    assert Points.call(ScratchRepo, c.user_id, nil, c.context) == 0
    stopped = Map.put(c.context, :fence, fn _ -> raise Dawarich.Imports.LeaseLost end)

    assert_raise Dawarich.Imports.LeaseLost, fn ->
      Points.call(ScratchRepo, c.user_id, data, stopped)
    end
  end
end
