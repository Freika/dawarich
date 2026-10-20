defmodule DawarichWeb.NativeMapModalsParityTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Dawarich.Test.ParityHTML

  @fixture "test/fixtures/map_ui/rails-1.16.0-panels.html"

  test "the create-visit modal renders the Rails modal markup" do
    dialog = %{
      id: nil,
      form: %{
        "name" => "",
        "started_at" => "2026-10-16T10:00",
        "ended_at" => "2026-10-16T11:00",
        "latitude" => "52.5",
        "longitude" => "13.4"
      },
      errors: [],
      places: [],
      place_id: nil,
      notes: [],
      note_error: nil,
      search: nil
    }

    native = render_component(&DawarichWeb.NativeMapVisit.dialog/1, dialog: dialog, locale: "en")
    assert shape(native) == shape(rails("modal-visit"))
  end

  test "the create-area modal renders the Rails modal markup" do
    dialog = %{
      id: nil,
      form: %{"name" => "", "radius" => nil, "latitude" => "52.5", "longitude" => "13.4"},
      errors: []
    }

    native =
      render_component(&DawarichWeb.NativeAreaDialog.dialog/1, dialog: dialog, locale: "en")

    assert shape(native) == shape(rails("modal-area")),
           ParityHTML.first_difference(shape(native), shape(rails("modal-area")))
  end

  test "the create-place modal renders the Rails modal markup with its tag chips" do
    tag = %{id: 3, name: "Favorite", icon: "⭐", color: "#3357FF"}

    dialog = %{
      id: nil,
      form: %{"name" => "", "latitude" => "52.5", "longitude" => "13.4", "note" => ""},
      errors: [],
      tags: [tag],
      nearby: nil
    }

    native =
      render_component(&DawarichWeb.NativeMapPlace.dialog/1, dialog: dialog, locale: "en")

    rails = rails("modal-place")

    assert without_tags(shape(native)) == without_tags(shape(rails)),
           ParityHTML.first_difference(without_tags(shape(native)), without_tags(shape(rails)))

    assert first_tag(shape(native)) == first_tag(shape(rails))
  end

  defp without_tags(nodes) when is_list(nodes),
    do: nodes |> Enum.reject(&tag_chip?/1) |> Enum.map(&without_tags/1)

  defp without_tags({tag, attrs, children}), do: {tag, attrs, without_tags(children)}
  defp without_tags(text), do: text

  defp first_tag(nodes) when is_list(nodes), do: Enum.find_value(nodes, &first_tag/1)

  defp first_tag({_, _, children} = node),
    do: if(tag_chip?(node), do: node, else: first_tag(children))

  defp first_tag(_), do: nil

  defp tag_chip?({"label", [{"class", "cursor-pointer"}], _}), do: true
  defp tag_chip?(_), do: false

  defp rails(name) do
    @fixture
    |> File.read!()
    |> String.split("<!-- section:")
    |> Enum.find_value(fn part ->
      case String.split(part, " -->\n", parts: 2) do
        [^name, markup] -> markup
        _ -> nil
      end
    end)
    |> String.replace(~s(class="modal z-[10000]"), ~s(class="modal z-[10000] modal-open"))
  end

  defp shape(html) do
    html
    |> String.replace(~r/ value="[^"]*"/, "")
    |> String.replace(~s( required="required"), ~s( required=""))
    |> String.replace(~r/ (role|aria-modal|aria-labelledby)="[^"]*"/, "")
    |> String.replace(~r/<input type="hidden" name="authenticity_token"[^>]*>/, "")
    |> ParityHTML.normalize()
  end
end
