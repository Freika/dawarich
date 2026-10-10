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

  test "native poster studio is a keyed hook root whose ignored islands are the stage and the controls" do
    {html, doc} = render()

    assert attribute(doc, "#native-poster-studio", "phx-hook") == ["PosterStudio"]
    assert attribute(doc, "[phx-update=ignore]", "id") == ["native-poster-stage", "native-poster-controls"]
    assert doc |> LazyHTML.query("#native-poster-stage [data-poster-map]") |> Enum.count() == 1
    assert doc |> LazyHTML.query("#native-poster-stage [data-poster-overlay]") |> Enum.count() == 1
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
    assert config["strings"]["open_failed"] == "Poster-Studio konnte nicht geöffnet werden: %{error}"
    refute Enum.any?(Map.values(config["strings"]), &String.contains?(&1, "translation missing"))
  end

  test "theme swatches name the first theme as the initial theme" do
    {_html, doc} = render()

    assert attribute(doc, "[data-poster-swatch]", "data-key") == ["noir", "ocean"]
  end
end
