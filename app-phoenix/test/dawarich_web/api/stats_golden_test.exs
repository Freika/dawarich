defmodule DawarichWeb.Api.StatsGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Test.ApiGolden

  @golden "test/fixtures/api_stats/golden.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users countries stats digests visits points flights)

  setup do
    Dawarich.ScratchRepo.query!("TRUNCATE phoenix.stats_point_counts", [], log: false)
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden #{kase["name"]}", %{port: port, upstream: upstream} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)

      for [table, rows] <- @kase["setup"], row <- rows do
        true = table in @tables

        ApiGolden.insert!(table, row)
      end

      ApiGolden.check(@kase, port, upstream)
    end
  end
end
