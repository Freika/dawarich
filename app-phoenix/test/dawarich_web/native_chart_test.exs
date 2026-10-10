defmodule DawarichWeb.NativeChartTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

  test "native chart carries localized single and multiple series without executable scripts" do
    data = [["März", 12.5], ["April", 20]]

    html =
      render_component(&DawarichWeb.NativeChart.chart/1,
        id: "distance",
        data: data,
        revision: "ready",
        label: "Entfernung",
        options: %{suffix: " km"}
      )

    document = LazyHTML.from_fragment(html)

    payload =
      document
      |> LazyHTML.query("[data-chart]")
      |> LazyHTML.attribute("data-chart")
      |> hd()
      |> Jason.decode!()

    assert payload["data"] == data
    assert payload["options"]["suffix"] == " km"
    assert LazyHTML.query(document, "table td") |> LazyHTML.text() =~ "März"
    series = [%{name: "Zu Fuß", data: data}]

    multiple =
      render_component(&DawarichWeb.NativeChart.chart/1,
        id: "multiple",
        data: series,
        revision: "ready",
        label: "Entfernung"
      )

    assert multiple =~ "Zu Fuß"
    assert multiple =~ "März"
    refute html =~ "<script"
    refute html =~ "data-controller"

    assert_raise ArgumentError, fn ->
      render_component(&DawarichWeb.NativeChart.chart/1,
        id: "distance",
        data: List.duplicate(["day", 1], 367),
        revision: "ready",
        label: "Distance"
      )
    end
  end

  test "heatmap links preserve zoned day bounds without a controller" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    heatmap = %{
      daily: %{"2026-03-29" => 1000},
      levels: %{p25: 1, p50: 2, p75: 3, p90: 4},
      active_days: 1
    }

    html =
      render_component(&DawarichWeb.HeatmapParts.heatmap/1,
        locale: "de",
        heatmap: heatmap,
        year: 2026,
        today: ~D[2026-12-31],
        unit: "km",
        native: true,
        zone: "Europe/Berlin"
      )

    document = LazyHTML.from_fragment(html)
    link = document |> LazyHTML.query("a[data-date='2026-03-29']")
    [href] = LazyHTML.attribute(link, "href")
    query = URI.decode_query(URI.parse(href).query)

    assert String.to_integer(query["end_at"]) - String.to_integer(query["start_at"]) + 1 ==
             23 * 3600

    assert LazyHTML.attribute(link, "aria-label") != []
    assert Enum.count(LazyHTML.query(document, "a[data-date]")) <= 366
    refute html =~ "RailsStimulus"
    refute html =~ "data-controller"
  end
end
