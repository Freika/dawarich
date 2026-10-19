defmodule DawarichWeb.MapShellParityTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  alias Dawarich.Test.{ParityHTML, RailsUser}
  @endpoint DawarichWeb.Endpoint

  @fixture "test/fixtures/map_ui/rails-1.16.0-shell.html"
  @sections [
    {"date-bar", "div.w-full.px-4.bg-base-100.border-b"},
    {"cluster", ".map-button-cluster"},
    {"panel-header", "#map-settings-panel .panel-header"},
    {"progress-badge", ".map-progress-badge"},
    {"webgl-error", "#maps-maplibre-container > div:first-child"},
    {"timeline-overlay", ".timeline-map-overlay"}
  ]

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-shell-#{id}@example.invalid",
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    html =
      RailsUser.signed_in(id)
      |> get("/map?start_at=2026-10-16&end_at=2026-10-18&locale=en")
      |> html_response(200)

    %{html: LazyHTML.from_document(html)}
  end

  for {name, selector} <- @sections do
    test "the map #{name} matches Rails 1.16.0", %{html: html} do
      assert fragment(html, unquote(selector)) == unquote(name) |> rails() |> fragment("body > *")
    end
  end

  test "the map page renders no missing translation", %{html: html} do
    refute LazyHTML.to_html(html) =~ "translation_missing"
  end

  defp rails(name) do
    @fixture
    |> File.read!()
    |> String.split(~r/<!-- section:/)
    |> Enum.find_value(fn part ->
      case String.split(part, " -->\n", parts: 2) do
        [^name, markup] -> LazyHTML.from_document("<html><body>" <> markup <> "</body></html>")
        _ -> nil
      end
    end)
  end

  defp fragment(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.to_html()
    |> mask_clock_links()
    |> ParityHTML.normalize()
  end

  defp mask_clock_links(html),
    do:
      Regex.replace(~r/href="\/map\/v2\?end_at=[^"&]*T23%3A59%3A59[^"]*"/, html, ~s(href="clock"))
end
