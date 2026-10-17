defmodule Dawarich.H3Test do
  use ExUnit.Case, async: true

  alias Dawarich.H3

  @fixture Path.expand("../fixtures/a12d1a/h3.json", __DIR__)

  test "every coordinate of the Rails h3 gem corpus lands in the gem's cell at resolutions 0 to 15" do
    %{"gem" => "3.7.4", "cases" => cases} = @fixture |> File.read!() |> Jason.decode!()
    assert length(cases) == 821

    mismatches =
      for %{"lat" => lat, "lng" => lng, "cells" => cells} <- cases,
          {cell, res} <- Enum.with_index(cells),
          H3.hex(H3.from_geo({lat, lng}, res)) != cell,
          do: {lat, lng, res, cell}

    assert mismatches == []
  end

  test "Rails' Berlin characterization coordinate is 881f191b27fffff at resolution 8" do
    assert H3.hex(H3.from_geo({52.107902115161316, 14.452712811406352}, 8)) == "881f191b27fffff"
  end

  test "integer coordinates work and a coordinate off the globe or a resolution above 15 is refused" do
    assert H3.hex(H3.from_geo({0, 0}, 0)) == H3.hex(H3.from_geo({0.0, 0.0}, 0))
    assert_raise ArgumentError, fn -> H3.from_geo({90.5, 0.0}, 8) end
    assert_raise FunctionClauseError, fn -> H3.from_geo({0.0, 0.0}, 16) end
  end
end
