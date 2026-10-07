defmodule Dawarich.A12f3bC01Test do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatUserWorker, as: Worker
  alias Dawarich.{DigestFixtures, Redis, Repo, Stats}
  alias Dawarich.Insights.Details.Digests

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    {:ok, _} = Redis.cache_command(["FLUSHDB"])
    kase = DigestFixtures.case!("berlin_yearly")
    DigestFixtures.load!(Repo, kase)
    opts = Keyword.delete(DigestFixtures.options(kase), :uuid) |> Keyword.put(:repo, Repo)
    Dawarich.Jobs.Ownership.put!(Repo, "command:stats.calculate_month", :oban)
    %{opts: opts}
  end

  @tag a12f3b_case: "C01a"
  test "native warming reaches retained consumers without a Rails cache write", %{opts: opts} do
    args = args()
    source = "dawarich/user_14101_countries_visited"
    {:ok, "OK"} = Redis.cache_command(["SET", source, "source-cache-cannot-satisfy-native-read"])
    assert Worker.run(Repo, args, opts) == :ok
    assert {:ok, [_ | _]} = Redis.cache_command(["KEYS", "phoenix/dawarich/user_14101_*"])

    assert {:ok, [_ | _]} =
             Redis.cache_command(["KEYS", "phoenix/insights/yearly_digest/14101/*"])

    assert {:ok, "source-cache-cannot-satisfy-native-read"} = Redis.cache_command(["GET", source])
    assert [[0]] = Repo.query!("SELECT count(*) FROM phoenix.rails_commands").rows

    user = %Dawarich.Accounts.User{id: 14101, plan: 1, settings: %{}, points_count: 0}
    context = Stats.context(user, opts[:now], true)
    index = Stats.index(user, context, true, opts[:now], repo: Repo)
    assert index.total_distance > 0
    assert is_list(index.countries_visited)
    assert is_list(index.cities_visited)
    assert is_integer(index.points.geocoded)
    assert {digest, false} = Digests.native_yearly(14101, 2025, stats(), opts)
    assert digest["travel_patterns"] != %{}
    key = "phoenix/" <> Digests.key(14101, 2025, digest["updated_at"])
    assert {:ok, ttl} = Redis.cache_command(["TTL", key])
    assert ttl in 1..3600

    for {suffix, expected} <- [
          {"countries_visited", index.countries_visited},
          {"cities_visited", index.cities_visited},
          {"total_distance", index.total_distance}
        ] do
      assert {:ok, <<"DW1", bytes::binary>>} =
               Redis.cache_command(["GET", "phoenix/dawarich/user_14101_#{suffix}"])

      assert %{value: ^expected} = :erlang.binary_to_term(bytes, [:safe])
    end

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM phoenix.stats_point_counts WHERE user_id=14101").rows

    assert {:ok, "OK"} =
             Redis.cache_command([
               "SET",
               String.replace_prefix(key, "phoenix/", ""),
               "source-yearly-snapshot"
             ])

    assert {:ok, bytes} = Redis.cache_command(["GET", key])
    assert {^digest, false} = Digests.native_yearly(14101, 2025, stats(), opts)
    assert {:ok, ^bytes} = Redis.cache_command(["GET", key])

    assert :ok =
             Dawarich.Stats.CacheInvalidation.call(Repo, %{
               "user_id" => 14101,
               "year" => 2025,
               "scope" => "all"
             })

    assert {:ok, nil} = Redis.cache_command(["GET", key])

    assert [[0]] =
             Repo.query!("SELECT count(*) FROM phoenix.stats_point_counts WHERE user_id=14101").rows

    Repo.query!(
      "UPDATE stats SET distance=distance+1000,updated_at=$1 WHERE user_id=14101 AND year=2025",
      [~N[2026-10-04 12:00:00]]
    )

    refreshed = Stats.index(user, context, true, opts[:now], repo: Repo)
    assert refreshed.total_distance > index.total_distance
    assert {fresh, false} = Digests.native_yearly(14101, 2025, stats(), opts)
    assert fresh["distance"] > digest["distance"]
    assert :ok = Dawarich.Points.DependentCaches.invalidate(14101, 2025, Repo)

    assert {:ok, nil} =
             Redis.cache_command([
               "GET",
               "phoenix/" <> Digests.key(14101, 2025, fresh["updated_at"])
             ])
  end

  @tag a12f3b_case: "C01b"
  test "warming partial failure retains source retry and processed ordering", %{opts: opts} do
    args = args()
    fault = %RuntimeError{message: "last native warm write failed"}
    hook = fn suffix -> if suffix == "points_geocoded_stats", do: raise(fault) end
    assert Worker.run(Repo, args, Keyword.put(opts, :before_warm_write, hook)) == {:error, fault}
    assert {:ok, [_ | _]} = Redis.cache_command(["KEYS", "phoenix/dawarich/user_14101_*"])
    assert [[0]] = Repo.query!("SELECT count(*) FROM phoenix.processed_commands").rows
    assert Worker.run(Repo, args, opts) == :ok
    assert Worker.run(Repo, args, opts) == :ok
    assert [[1]] = Repo.query!("SELECT count(*) FROM phoenix.processed_commands").rows
    assert [[0]] = Repo.query!("SELECT count(*) FROM phoenix.rails_commands").rows
  end

  defp args do
    event = Ecto.UUID.generate()

    %{
      "user_id" => 14101,
      "time_zone" => "Europe/Berlin",
      "source_job_id" => event,
      "event_id" => event
    }
  end

  defp stats do
    result = Repo.query!("SELECT * FROM stats WHERE user_id=14101")
    Enum.map(result.rows, &Map.new(Enum.zip(result.columns, &1)))
  end
end
