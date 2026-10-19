defmodule DawarichWeb.MapPanelsParityTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  alias Dawarich.Test.{ParityHTML, RailsUser}
  @endpoint DawarichWeb.Endpoint

  @fixture "test/fixtures/map_ui/rails-1.16.0-panels.html"
  @sections [
    {"tab-search", ~s([data-tab-content="search"])},
    {"tab-layers", ~s([data-tab-content="layers"])},
    {"tab-tools", ~s([data-tab-content="tools"])}
  ]

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-panels-#{id}@example.invalid",
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
    document |> LazyHTML.query(selector) |> LazyHTML.to_html() |> ParityHTML.normalize()
  end
end
