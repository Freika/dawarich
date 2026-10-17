defmodule Dawarich.MapMatching.ComposerTest do
  use ExUnit.Case, async: true
  alias Dawarich.MapMatching.Composer

  test "composition preserves source order and discontinuities without synthetic connectors" do
    path = Composer.call([[[13.4, 52.5], [13.41, 52.51]], [[14, 53], [14.1, 53.1]]])
    assert path.__struct__ == Geo.MultiLineString
    assert path.srid == 4326
    assert path.coordinates == [[{13.4, 52.5}, {13.41, 52.51}], [{14, 53}, {14.1, 53.1}]]
  end

  test "short lines are dropped and empty composition is nil" do
    assert Composer.call([nil, [], [[13, 52]]]) == nil
    assert Composer.call([]) == nil
    path = Composer.call([[[1, 2]], [[3, 4], [5, 6]], []])
    assert path.coordinates == [[{3, 4}, {5, 6}]]
  end
end
