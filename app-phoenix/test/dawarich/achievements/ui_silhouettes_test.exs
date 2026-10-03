defmodule Dawarich.Achievements.UiSilhouettesTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.UiSilhouettes

  @square "MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))"
  @wide "MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.75 51.5,12.75 51.25,12.25 51.25)))"

  setup do
    rows("TRUNCATE countries,regions RESTART IDENTITY")
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    country("DE", @square)
    :ok
  end

  defp country(code, wkt),
    do:
      rows(
        "INSERT INTO countries(iso_a2,iso_a3,name,geom,created_at,updated_at) VALUES($1,$1,$1,ST_GeomFromText($2,4326),now(),now())",
        [code, wkt]
      )

  defp reshape(code, wkt),
    do: rows("UPDATE countries SET geom=ST_GeomFromText($2,4326) WHERE iso_a2=$1", [code, wkt])

  test "card silhouettes are cached per level and code, a missing shape included" do
    first = UiSilhouettes.cards(ScratchRepo, "country", ["DE", "FR"])
    assert Map.keys(first) == ["DE"]

    reshape("DE", @wide)
    country("FR", @wide)

    assert UiSilhouettes.cards(ScratchRepo, "country", ["DE", "FR"]) == first
    assert UiSilhouettes.cards(ScratchRepo, "subdivision", ["DE"]) == %{}
  end

  test "collection silhouettes are cached by key and member set" do
    country("FR", @wide)
    europe = UiSilhouettes.collection(ScratchRepo, ["FR", "DE"], "continent_europe")
    reshape("DE", @wide)

    assert UiSilhouettes.collection(ScratchRepo, ["DE", "FR"], "continent_europe") == europe
    refute UiSilhouettes.collection(ScratchRepo, ["DE"], "continent_europe") == europe
    refute UiSilhouettes.collection(ScratchRepo, ["DE", "FR"], "continent_asia") == europe
  end

  test "the viewBox rounds and prints its numbers as Ruby's Float#round(4) and #to_s do" do
    country(
      "XX",
      "MULTIPOLYGON (((12.34565 51.30005,12.34565 51.34565,12.40005 51.34565,12.40005 51.30005,12.34565 51.30005)))"
    )

    assert %{"XX" => %{"viewbox" => "12.3457 -51.3457 0.0544 0.0456"}} =
             UiSilhouettes.cards(ScratchRepo, "country", ["XX"])
  end
end
