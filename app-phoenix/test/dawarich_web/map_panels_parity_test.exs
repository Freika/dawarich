defmodule DawarichWeb.MapPanelsParityTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  alias Dawarich.Test.{ParityHTML, RailsUser}
  @endpoint DawarichWeb.Endpoint

  @fixture "test/fixtures/map_ui/rails-1.16.0-panels.html"
  @sections [
    {"tab-search", ~s([data-tab-content="search"])},
    {"tab-layers", ~s([data-tab-content="layers"])},
    {"tab-tools", ~s([data-tab-content="tools"])},
    {"tab-settings", ~s([data-tab-content="settings"])},
    {"tab-timeline", ~s([data-tab-content="timeline-feed"])},
    {"replay-panel", ".replay-panel"},
    {"onboarding", "#getting_started"}
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
      phoenix = fragment(html, unquote(selector))
      rails = unquote(name) |> rails() |> fragment("body > *")
      dump(unquote(name), phoenix, rails)
      assert phoenix == rails
    end
  end

  defp client_state(nodes) when is_list(nodes),
    do: nodes |> Enum.reject(&user_tag?/1) |> Enum.map(&client_state/1)

  defp client_state({tag, attrs, children}) do
    form = List.keyfind(attrs, "form", 0)
    token = List.keymember?(attrs, "data-token", 0)

    value? =
      tag == "input" and
        List.keyfind(attrs, "type", 0) in Enum.map(~w(color number range url text), &{"type", &1})

    attrs =
      attrs
      |> Enum.reject(fn {name, _} ->
        name in ~w(checked selected form) or
          (form != nil and name == "name" and {"type", "hidden"} not in attrs) or
          (token and name == "name") or (value? and name == "value")
      end)
      |> checked_badge()

    children =
      if token or {"class", "text-xs opacity-60 tabular-nums"} in attrs or
           {"class", "label-text-alt"} in attrs,
         do: [],
         else: client_state(children)

    {tag, attrs, children}
  end

  defp client_state(text), do: text

  defp checked_badge(attrs) do
    if List.keymember?(attrs, "data-checked-style", 0) do
      attrs
      |> List.keydelete("style", 0)
      |> Enum.map(fn
        {"class", value} ->
          {"class", value |> String.split() |> List.delete("badge-outline") |> Enum.join(" ")}

        attr ->
          attr
      end)
    else
      attrs
    end
  end

  defp user_tag?({"label", _, children}) do
    Enum.any?(children, fn
      {"input", attrs, _} ->
        {"name", "place_tag_ids[]"} in attrs and {"value", "untagged"} not in attrs

      _ ->
        false
    end)
  end

  defp user_tag?({"div", [{"class", "timeline-rail__section"}], _}), do: true
  defp user_tag?({"form", attrs, children}),
    do: {"action", "/imports"} in attrs or ({"method", "dialog"} in attrs and children == [])

  defp user_tag?({"div", [{"class", "flex justify-end"}], [{"a", attrs, _}]}),
    do: {"href", "/imports/new"} in attrs

  defp user_tag?({"div", [{"class", "text-xs text-base-content/60 mt-2"}], [text]}),
    do: text =~ "automatically detected"

  defp user_tag?({"svg", attrs, _}), do: {"shape-rendering", "crispEdges"} in attrs
  defp user_tag?(_), do: false

  defp dump(name, phoenix, rails) do
    if dir = System.get_env("PARITY_DUMP") do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, name <> ".phoenix"), phoenix)
      File.write!(Path.join(dir, name <> ".rails"), rails)
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
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.to_html()
    |> ParityHTML.normalize()
    |> client_state()
    |> inspect(pretty: true, limit: :infinity, printable_limit: :infinity)
  end
end
