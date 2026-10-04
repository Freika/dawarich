defmodule Dawarich.Posters.GeometryTest do
  use ExUnit.Case, async: true
  alias Dawarich.Posters.Geometry

  @tag mutation: "wrap"
  test "frame includes longitude wrap and excludes data outside Mercator bounds" do
    for name <-
          ~w(points_gap_boundaries antimeridian outside_frame clamps_low clamps_high clamps_zero) do
      state = load(name)

      assert Geometry.intersects?(state["track"], state["before"]["settings"]) ==
               state["geometry"]["intersects"]
    end

    settings = %{"lat" => "51.3397", "lon" => "12.3731", "distance" => "6000"}
    refute Geometry.intersects?(%{"coordinates" => [[[12.3731, 86.0]]]}, settings)
    refute Geometry.intersects?(%{"coordinates" => [[[12.3731, -86.0]]]}, settings)

    assert Geometry.intersects?(%{"coordinates" => [[[12.3731, 51.3397]]]}, settings, %{
             width: 1200,
             height: 1600
           })
  end

  @tag mutation: "width"
  test "distance opacity width and subtitle match Rails boundary fixtures" do
    for name <- ~w(clamps_low clamps_high clamps_zero render_title_0 render_title_1) do
      state = load(name)
      settings = state["before"]["settings"]
      assert Geometry.distance(settings) == state["geometry"]["distance"]
      assert Geometry.opacity(settings) == state["geometry"]["route_opacity"]
      assert Geometry.width(settings) == state["geometry"]["route_width"]

      assert Geometry.subtitle(settings, state["locale"]) ==
               state["render_job"]["text"]["subtitle"]
    end

    assert Geometry.distance(%{}) == 6000
    assert Geometry.distance(%{"distance" => "garbage"}) == 500
    assert Geometry.distance(%{"distance" => "1_200 meters"}) == 1200
    assert Geometry.width(%{}) == 1.0
    assert Geometry.width(%{"route_width" => nil}) == 1.0
    assert Geometry.opacity(%{"route_opacity" => "50garbage"}) == 0.5
    assert Geometry.opacity(%{}) == 1.0
    settings = %{"start_at" => "2026-10-03T01:00:00+09:00", "end_at" => "2026-10-03T10:00:00Z"}
    assert Geometry.subtitle(settings, "en") == "Oct 2, 2026 – Oct 3, 2026"
  end

  defp load(name), do: File.read!("test/fixtures/posters/" <> name <> ".json") |> Jason.decode!()
end
