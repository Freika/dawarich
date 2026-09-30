defmodule DawarichWeb.TripFormatTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.TripFormat

  test "card distances round half away from zero in the user's unit; no distance is 0" do
    assert TripFormat.distance(999_500, 1000) == 1000
    assert TripFormat.distance(1499, 1000) == 1
    assert TripFormat.distance(16_093, 1609.34) == 10
    assert TripFormat.distance(nil, 1000) == 0
  end
end
