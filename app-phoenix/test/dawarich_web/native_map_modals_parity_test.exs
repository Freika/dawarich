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
