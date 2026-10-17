defmodule DawarichWeb.NativeMonthMapRangeTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest

  test "monthly preview dates admit both geometry readers across daylight saving" do
    for {zone, first, last} <- [
          {"Europe/Berlin", 1_709_247_600, 1_711_922_399},
          {"UTC", 1_709_251_200, 1_711_929_599}
        ] do
      html =
        render_component(&DawarichWeb.StatsLive.NativeMonthMap.render/1,
          data: %{year: 2024, month: 3, period: %{zone: zone}, data: %{stat: true}},
          locale: "en"
        )

      [encoded] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-map-config]")
        |> LazyHTML.attribute("data-map-config")

      config = Jason.decode!(encoded)
      assert {:ok, ^first} = Dawarich.Tiles.Http.strict_timestamp(config["range"]["startAt"])
      assert {:ok, ^last} = Dawarich.Tiles.Http.strict_timestamp(config["range"]["endAt"])
      assert {:ok, _} = DateTime.from_iso8601(config["range"]["startAt"]) |> iso_result()
      assert {:ok, _} = DateTime.from_iso8601(config["range"]["endAt"]) |> iso_result()
    end
  end

  defp iso_result({:ok, date, _}), do: {:ok, date}
  defp iso_result(other), do: other
end
