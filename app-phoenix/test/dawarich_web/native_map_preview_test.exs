defmodule DawarichWeb.NativeMapPreviewTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "preview insertion carries only resource and range metadata with localized labels" do
    html =
      render_component(&DawarichWeb.NativeMapPreview.preview/1,
        id: "preview-7",
        locale: "de",
        config: %{
          "tripId" => 7,
          "kind" => "trip",
          "path" => [[13, 52]],
          "api_key" => "synthetic-key",
          "range" => %{"timezone" => "Europe/Berlin", "password" => "synthetic-key"},
          "labels" => %{"map_info.points" => "override"}
        }
      )

    assert html =~ "phx-hook=\"MapPreview\""

    [config] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-map-config]")
      |> LazyHTML.attribute("data-map-config")

    data = Jason.decode!(config)
    assert data["tripId"] == 7
    assert data["range"]["timezone"] == "Europe/Berlin"
    assert data["labels"]["map_info.points"] == "Punkte"
    refute config =~ "synthetic-key"
    refute config =~ "path"
    refute config =~ "override"
  end

  test "public stats preview has only its public capability and bounded extent" do
    html =
      render_component(&DawarichWeb.NativeMapPreview.preview/1,
        id: "stats-preview",
        config: %{
          "kind" => "stats",
          "uuid" => "public-share",
          "bounds" => %{"point_count" => 2, "min_lng" => 13, "owner" => "synthetic-key"},
          "user_id" => 7
        }
      )

    assert html =~ "public-share"
    assert html =~ "point_count"
    refute html =~ "user_id"
    refute html =~ "synthetic-key"
  end
end
