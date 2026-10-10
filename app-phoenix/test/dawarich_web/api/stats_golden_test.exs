defmodule DawarichWeb.Api.StatsGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Test.ApiGolden

  @golden "test/fixtures/api_stats/golden.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users countries stats digests visits points flights)

  setup do
    Dawarich.FixtureCleanup.delete!(Dawarich.ScratchRepo, ~w(phoenix.stats_point_counts))
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  for kase <- @golden["cases"] do
    @kase if(kase["name"] in ~w(rails_borders_anonymous rails_visited_epoch),
            do: Map.put(kase, "expect", "own"),
            else: kase
          )
    @tag golden_case: String.to_atom(kase["name"])
    test "golden #{kase["name"]}", %{port: port, upstream: upstream} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)

      for [table, rows] <- @kase["setup"], row <- rows do
        true = table in @tables

        ApiGolden.insert!(table, row)
      end

      if @kase["name"] == "rails_visited_epoch" do
        start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
        recorded = "test/fixtures/api_stats/visited_epoch.json" |> File.read!() |> Jason.decode!()
        assert Map.drop(recorded, ["expect", "cache"]) == Map.drop(@kase, ["expect"])

        for {key, token} <- recorded["cache"] do
          assert {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", key, token])
        end

        try do
          ApiGolden.check(@kase, port, upstream)
        after
          for {key, _} <- recorded["cache"], do: Dawarich.Redis.cache_command(["DEL", key])
        end
      else
        ApiGolden.check(@kase, port, upstream)
      end
    end
  end
end
