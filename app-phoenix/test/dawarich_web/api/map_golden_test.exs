defmodule DawarichWeb.Api.MapGoldenTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_golden: true

  alias Dawarich.Test.ApiGolden

  @golden "test/golden_captures/api_map.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users countries point_sources tracks track_segments points)

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  setup_all do
    {:ok, golden: File.read!("test/golden_captures/api_map.json") |> Jason.decode!()}
  end

  for kase <- @golden["cases"] do
    @case_name kase["name"]
    test "golden #{kase["name"]}", %{port: port, upstream: puma, golden: golden} do
      kase = Enum.find(golden["cases"], &(&1["name"] == @case_name))
      Enum.each(kase["env"], fn {name, value} -> System.put_env(name, value) end)

      for [table, rows] <- golden["setups"][kase["setup"]], row <- rows do
        true = table in @tables
        ApiGolden.insert!(table, row)
      end

      before = digests()
      ApiGolden.check(kase, port, puma, float_precision: 8, float_fields: ["avg_speed"])
      assert digests() == before
      assert Dawarich.Test.ApiCapturedState.rows(@tables) == kase["after"]
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
