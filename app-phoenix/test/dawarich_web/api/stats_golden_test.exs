defmodule DawarichWeb.Api.StatsGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat
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

        Repo.query!(
          "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table}, $1::text::json)",
          [exact_json(row)]
        )
      end

      ApiGolden.check(@kase, port, upstream)
    end
  end

  defp exact_json(value) when is_float(value), do: RubyFloat.to_s(value)

  defp exact_json(value) when is_map(value),
    do:
      "{" <>
        Enum.map_join(value, ",", fn {k, v} -> "#{Jason.encode!(k)}:#{exact_json(v)}" end) <> "}"

  defp exact_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &exact_json/1) <> "]"

  defp exact_json(value), do: Jason.encode!(value)
end
