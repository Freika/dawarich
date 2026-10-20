defmodule DawarichWeb.NativeMapStudiosParityTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  alias Dawarich.Test.{NativeAdminUI, ParityHTML, RailsUser}
  @endpoint DawarichWeb.Endpoint
  @fixture "test/fixtures/map_ui/rails-1.16.0-studios.html"
  @accessible_controls %{
    "data-native-poster-date-start" => "Start date and time",
    "data-native-poster-date-end" => "End date and time",
    "data-native-poster-layout" => "Layout",
    "data-native-poster-opacity" => "Track opacity",
    "data-native-poster-width" => "Track width"
  }

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-studios-#{id}@example.invalid",
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    html =
      RailsUser.signed_in(id)
      |> get("/map?start_at=2026-10-16&end_at=2026-10-18&locale=en")
      |> html_response(200)

    %{html: html}
  end

  for kind <- ~w(poster video) do
    test "the map #{kind} studio matches Rails 1.16.0", %{html: html} do
      name = unquote(kind) <> "-studio"
      studio = html |> LazyHTML.from_document() |> LazyHTML.query("#" <> name)
      assert NativeAdminUI.labels(LazyHTML.to_html(studio)) == []
      phoenix = studio |> LazyHTML.to_tree() |> studio_accessibility() |> ParityHTML.normalize()
      phoenix = if unquote(kind) == "poster", do: poster_resilience(phoenix), else: phoenix

      rails =
        @fixture
        |> File.read!()
        |> String.split("<!-- section:")
        |> Enum.find_value(fn part ->
          case String.split(part, " -->\n", parts: 2) do
            [^name, markup] -> markup
            _ -> nil
          end
        end)
        |> ParityHTML.normalize()
        |> without_save_form()

      if dir = System.get_env("PARITY_DUMP") do
        File.mkdir_p!(dir)

        File.write!(
          Path.join(dir, name <> ".phoenix"),
          inspect(phoenix, pretty: true, limit: :infinity)
        )

        File.write!(
          Path.join(dir, name <> ".rails"),
          inspect(rails, pretty: true, limit: :infinity)
        )
      end

      assert phoenix == rails, ParityHTML.first_difference(phoenix, rails)
    end
  end

  defp studio_accessibility(nodes) when is_list(nodes),
    do: Enum.map(nodes, &studio_accessibility/1)

  defp studio_accessibility({tag, attrs, children}) do
    additions =
      for {key, label} <- @accessible_controls, {^key, _} <- attrs do
        assert {"aria-label", label} in attrs
        {"aria-label", label}
      end

    {tag, attrs -- additions, studio_accessibility(children)}
  end

  defp studio_accessibility(text), do: text

  @poster_resilience %{
    "flex flex-wrap items-center justify-between gap-4 border-b border-base-content/10 bg-base-200 px-4 py-2 lg:flex-nowrap" =>
      "flex items-center justify-between gap-4 border-b border-base-content/10 bg-base-200 px-4 py-2",
    "flex flex-wrap items-center gap-2 min-w-0 lg:flex-nowrap" =>
      "flex items-center gap-2 min-w-0",
    "flex min-h-0 flex-1 flex-col lg:flex-row" => "flex min-h-0 flex-1",
    "relative flex h-[36vh] min-w-0 shrink-0 flex-col items-center justify-center overflow-hidden p-6 lg:h-auto lg:flex-1 lg:shrink" =>
      "relative flex min-w-0 flex-1 flex-col items-center justify-center overflow-hidden p-6",
    "flex min-h-0 w-full flex-1 flex-col border-t border-base-content/10 bg-base-200 lg:w-96 lg:flex-none lg:border-l lg:border-t-0" =>
      "flex w-96 shrink-0 flex-col border-l border-base-content/10 bg-base-200",
    "btn btn-primary btn-sm h-auto w-full py-1.5" => "btn btn-primary btn-sm w-full",
    "btn btn-ghost btn-xs h-auto w-full gap-1 py-1 opacity-70" =>
      "btn btn-ghost btn-xs w-full gap-1 opacity-70"
  }
  defp poster_resilience(nodes) when is_list(nodes), do: Enum.map(nodes, &poster_resilience/1)

  defp poster_resilience({tag, attrs, children}) do
    attrs =
      Enum.map(attrs, fn
        {"class", value} -> {"class", Map.get(@poster_resilience, value, value)}
        attr -> attr
      end)

    {tag, attrs, poster_resilience(children)}
  end

  defp poster_resilience(text), do: text

  defp without_save_form(nodes) when is_list(nodes),
    do: nodes |> Enum.reject(&save_form?/1) |> Enum.map(&without_save_form/1)

  defp without_save_form({tag, attrs, children}), do: {tag, attrs, without_save_form(children)}
  defp without_save_form(text), do: text
  defp save_form?({"form", attrs, _}), do: {"action", "/posters"} in attrs
  defp save_form?(_), do: false
end
