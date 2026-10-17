defmodule DawarichWeb.Api.StatsGoldenTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_golden: true

  alias Dawarich.Test.ApiGolden

  @golden "test/golden_captures/api_stats.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users countries stats digests visits points flights)

  setup do
    Dawarich.FixtureCleanup.delete!(Dawarich.ScratchRepo, ~w(phoenix.stats_point_counts))
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  setup_all do
    {:ok, golden: File.read!("test/golden_captures/api_stats.json") |> Jason.decode!()}
  end

  for kase <- @golden["cases"] do
    @case_name kase["name"]
    test "golden #{kase["name"]}", %{port: port, upstream: upstream, golden: golden} do
      kase = Enum.find(golden["cases"], &(&1["name"] == @case_name))
      Enum.each(kase["env"], fn {name, value} -> System.put_env(name, value) end)

      for [table, rows] <- kase["setup"], row <- rows do
        true = table in @tables

        ApiGolden.insert!(table, row)
      end

      if kase["name"] == "rails_visited_epoch" do
        start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

        recorded =
          "test/golden_captures/api_stats_visited_epoch.json" |> File.read!() |> Jason.decode!()

        assert Map.drop(recorded, ["expect", "cache"]) == Map.drop(kase, ["expect"])

        for {key, token} <- recorded["cache"] do
          assert {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", key, token])
        end

        try do
          ApiGolden.check(kase, port, upstream)
        after
          for {key, _} <- recorded["cache"], do: Dawarich.Redis.cache_command(["DEL", key])
        end
      else
        ApiGolden.check(kase, port, upstream)
      end

      assert Dawarich.Test.ApiCapturedState.rows(@tables) == kase["after"]
    end
  end
end
