defmodule Dawarich.Achievements.RegistryTest do
  use ExUnit.Case, async: true

  alias Dawarich.Achievements.Registry

  test "loads the exported registry in Rails order" do
    assert Registry.all() |> Enum.take(3) |> Enum.map(& &1.key) ==
             ~w(border_hopper globetrotter world_traveler)

    assert Registry.find("country_de").level == "subdivision"
    assert Registry.announcer("DE-SN").key == "country_de"
    assert Registry.announcer("LU").key == "continent_europe"
  end

  test "geography visibility follows Rails' rule" do
    assert Registry.visible_geography?("DE")
    assert Registry.visible_geography?("DE-SN")
    assert Registry.visible_geography?("LU")
    refute Registry.visible_geography?("XX")
    refute Registry.visible_geography?("ZZ-99")
  end

  test "every exported definition carries a name in each available locale" do
    for d <- Registry.all(),
        l <- Dawarich.I18n.available_locales(),
        do: assert(is_binary(d.names[l]))
  end
end
