defmodule DawarichWeb.NativePosterStudioTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias DawarichWeb.NativePosterStudio

  @themes [%{key: "noir", name: "Noir"}, %{key: "ocean", name: "Ocean"}]

  defp render(attrs \\ %{}) do
    html =
      render_component(
        &NativePosterStudio.poster_studio/1,
        Map.merge(%{themes: @themes, locale: "de", fixed_range_label: nil}, attrs)
      )

    {html, LazyHTML.from_fragment(html)}
  end

  defp attribute(doc, selector, name),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  test "native poster studio is a keyed hook root whose ignored islands hold only browser-owned state" do
    {html, doc} = render()

    assert attribute(doc, "#native-poster-studio", "phx-hook") == ["PosterStudio"]

    assert attribute(doc, "[phx-update=ignore]", "id") ==
             ~w(native-poster-dates native-poster-stage native-poster-controls native-poster-actions)

    {_html, trip} = render(%{fixed_range_label: "1. Okt. 2026 – 2. Okt. 2026"})

    assert attribute(trip, "[phx-update=ignore]", "id") ==
             ~w(native-poster-stage native-poster-controls native-poster-actions)

    assert trip |> LazyHTML.query("[data-poster-date-start]") |> Enum.count() == 0
    assert doc |> LazyHTML.query("#native-poster-stage [data-poster-map]") |> Enum.count() == 1

    assert doc |> LazyHTML.query("#native-poster-stage [data-poster-overlay]") |> Enum.count() ==
             1

    assert doc |> LazyHTML.query("dialog[data-poster-dialog]") |> Enum.count() == 1
    assert attribute(doc, "dialog[data-poster-dialog]", "phx-mounted") |> hd() =~ "ignore_attrs"

    refute html =~ ~r/data-controller|data-action|turbo|stimulus|signed-stream-name|api_key/i
  end

  test "studio config carries localized strings and digested font URLs only" do
    {_html, doc} = render()
    [json] = attribute(doc, "#native-poster-studio", "data-poster-config")
    config = Jason.decode!(json)

    assert Map.keys(config) |> Enum.sort() == ["fonts", "strings"]
    assert config["fonts"]["oswald-700"] =~ ~r{^/assets/poster/oswald-700}

    assert config["strings"]["open_failed"] ==
             "Poster-Studio konnte nicht geöffnet werden: %{error}"

    refute Enum.any?(Map.values(config["strings"]), &String.contains?(&1, "translation missing"))
  end

  test "theme swatches name the first theme as the initial theme" do
    {_html, doc} = render()

    assert attribute(doc, "[data-poster-swatch]", "data-key") == ["noir", "ocean"]
  end

  test "layout options follow the native layout catalogue with localized labels" do
    {_html, doc} = render()
    source = File.read!(Path.expand("../../assets/js/poster/data/layouts.js", __DIR__))
    catalogue = Regex.scan(~r/(?:paper|pixels)\("([a-z0-9-]+)"/, source, capture: :all_but_first)

    assert attribute(doc, "[data-poster-layout] option", "value") == List.flatten(catalogue)

    assert attribute(doc, "[data-poster-layout] optgroup", "label") == [
             "Drucken",
             "Soziales",
             "Hintergrundbild"
           ]

    assert attribute(doc, "[data-poster-layout] option[selected]", "value") == ["print-a3"]

    assert doc |> LazyHTML.query("[data-poster-layout] option[value=print-a3]") |> LazyHTML.text() |> String.trim() ==
             "A3 Hochformat"
  end

  test "each poster control is rendered once with its label and Rails defaults" do
    {_html, doc} = render()

    for name <-
          ~w(layout layout-dims title subtitle coords font text-toggle opacity width format dpi summary download date-start date-end load) do
      assert doc |> LazyHTML.query("[data-poster-#{name}]") |> Enum.count() == 1, name
    end

    assert attribute(doc, "[data-poster-layer]", "data-poster-layer") ==
             ~w(roads water landuse buildings rail boundaries)

    assert attribute(doc, "[data-poster-layer][checked]", "data-poster-layer") ==
             ~w(roads water landuse)

    assert attribute(doc, "[data-poster-font] option[selected]", "value") == ["oswald"]
    assert attribute(doc, "[data-poster-dpi] option[selected]", "value") == ["300"]
    assert attribute(doc, "[data-poster-format] option", "value") == ~w(png pdf)
    assert attribute(doc, "[data-poster-range]", "data-poster-range") == ~w(today week month)
    assert doc |> LazyHTML.query("[data-poster-token]") |> Enum.count() == 12
  end
end
