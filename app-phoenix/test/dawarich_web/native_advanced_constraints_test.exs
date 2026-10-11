defmodule DawarichWeb.NativeAdvancedConstraintsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "advanced form keeps the saved fog threshold within browser constraints so Live mode can submit" do
    html =
      render_component(&DawarichWeb.NativeMapSettingsAdvanced.advanced/1,
        saved: Dawarich.Settings.MapForm.defaults(),
        locale: "en"
      )

    input = html |> LazyHTML.from_fragment() |> LazyHTML.query("input[name=fog_of_war_threshold]")
    value = input |> LazyHTML.attribute("value") |> hd() |> String.to_integer()
    maximum = input |> LazyHTML.attribute("max") |> hd() |> String.to_integer()
    assert value <= maximum
    assert value == 10
  end
end
