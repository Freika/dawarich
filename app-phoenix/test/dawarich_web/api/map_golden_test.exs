defmodule DawarichWeb.Api.MapGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Test.ApiGolden

  @golden "test/fixtures/api_map/golden.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users countries point_sources tracks track_segments points)

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  for kase <- @golden["cases"] do
    @kase if(
            kase["name"] in ~w(rails_point_tiles rails_tracked_months rails_point_update rails_points_bulk_destroy),
            do: Map.put(kase, "expect", "own"),
            else: kase
          )
    test "golden #{kase["name"]}", %{port: port, upstream: puma} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)

      for [table, rows] <- @golden["setups"][@kase["setup"]], row <- rows do
        true = table in @tables
        ApiGolden.insert!(table, row)
      end

      before = digests()
      ApiGolden.check(@kase, port, puma, float_precision: 8, float_fields: ["avg_speed"])
      assert digests() == before
    end
  end

  defp digests do
    Repo.query!("SELECT set_config('TimeZone', 'UTC', true)")

    for table <- @tables do
      Repo.query!(
        "SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY id), '')) FROM #{table} t"
      ).rows
    end
  end
end
