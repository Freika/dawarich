defmodule DawarichWeb.NativeMapHostTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "native host configuration never exposes credentials supplied outside its scalar contract" do
    html =
      render_component(&DawarichWeb.NativeMapHost.map_host/1,
        id: "native-map",
        config: %{
          "namespace" => "synthetic-owner",
          "revision" => 1,
          "api_key" => "synthetic-root-credential",
          "range" => %{
            "startAt" => "2026-10-01",
            "endAt" => "2026-10-02",
            "timezone" => "Europe/Berlin",
            "password" => "synthetic-range-credential"
          },
          "mapOptions" => %{
            "center" => [13, 52],
            "zoom" => 4,
            "apiKey" => "synthetic-map-credential"
          }
        }
      )

    refute html =~ "synthetic-root-credential"
    refute html =~ "synthetic-range-credential"
    refute html =~ "synthetic-map-credential"

    [encoded] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-map-config]")
      |> LazyHTML.attribute("data-map-config")

    data = Jason.decode!(encoded)
    assert data["range"]["timezone"] == "Europe/Berlin"
    assert data["mapOptions"]["center"] == [13, 52]
    assert data["revision"] == 1
  end
end
