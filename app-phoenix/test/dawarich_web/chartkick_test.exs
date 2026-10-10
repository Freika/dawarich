defmodule DawarichWeb.ChartkickTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Test.ParityHTML

  @rails "test/fixtures/stats_corpus.json"
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("chart")

  defp script(html), do: Regex.run(~r/<script>.*<\/script>/s, html) |> hd()

  test "the chart is Chartkick's column_chart output, with the container ignored by LiveView patches" do
    html =
      render_component(&DawarichWeb.Chartkick.column_chart/1,
        id: "chart-corpus",
        height: "200px",
        data: [["März", 12], ["April", nil], [3, 0]],
        options: [
          suffix: " km",
          xtitle: "Tage & <Nacht>",
          colors: ["#397bb5"],
          library: [
            datasets: [borderWidth: 0, bar: [minBarLength: 4]],
            interaction: [mode: "index", intersect: false]
          ]
        ]
      )

    assert script(html) == script(@rails)
    assert html =~ ~s(<div id="chart-corpus" )
    assert html =~ ~s(phx-update="ignore")
    assert ParityHTML.normalize(html) == ParityHTML.normalize(@rails)
  end
end
