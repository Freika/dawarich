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

  test "native density label is localized without markup or unvalidated locale" do
    for {locale, expected, word} <- [{"de", "de", "Punkte"}, {"unknown-locale", "en", "points"}] do
      html =
        render_component(&DawarichWeb.NativeMapHost.map_host/1,
          id: "native-map",
          config: %{},
          locale: locale
        )

      [encoded] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-map-config]")
        |> LazyHTML.attribute("data-map-config")

      data = Jason.decode!(encoded)
      assert data["locale"] == expected
      assert data["hexagonLabel"] == "{count} " <> word

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-map-loading][role=status]")
             |> LazyHTML.text()
             |> String.trim() ==
               DawarichWeb.Translate.t(expected, "javascript.common.loading", %{})
    end
  end

  test "photo popup labels use the host locale and ignore caller overrides" do
    html =
      render_component(&DawarichWeb.NativeMapHost.map_host/1,
        id: "native-map",
        locale: "de",
        config: %{"photoLabels" => %{"map_info.photo" => "synthetic-override"}}
      )

    [encoded] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-map-config]")
      |> LazyHTML.attribute("data-map-config")

    labels = Jason.decode!(encoded)["photoLabels"]
    assert labels["map_info.photo"] == "Foto"
    assert labels["map_info.source"] == "Quelle"
    refute html =~ "synthetic-override"
  end

  test "entity popup labels are localized with bounded interpolation tokens" do
    html =
      render_component(&DawarichWeb.NativeMapHost.map_host/1,
        id: "native-map",
        locale: "de",
        config: %{"entityLabels" => %{"map_info.time" => "synthetic-override"}}
      )

    [encoded] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-map-config]")
      |> LazyHTML.attribute("data-map-config")

    labels = Jason.decode!(encoded)["entityLabels"]
    assert labels["map_info.time"] == "Zeit"
    assert labels["anomalies.low_accuracy"] =~ "{accuracy}"
    assert labels["anomalies.low_accuracy"] =~ "{threshold}"
    refute html =~ "synthetic-override"
  end

  test "native live mode configuration follows the saved flag and scalar host contract" do
    for enabled <- [true, false] do
      config =
        DawarichWeb.MapLive.NativeConfig.build(
          %{saved: %{"live_map_enabled" => enabled}},
          %{},
          %{},
          ""
        )

      assert config["liveEnabled"] == enabled

      html =
        render_component(&DawarichWeb.NativeMapHost.map_host/1, id: "native-map", config: config)

      [encoded] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-map-config]")
        |> LazyHTML.attribute("data-map-config")

      assert Jason.decode!(encoded)["liveEnabled"] == enabled
    end
  end
end
