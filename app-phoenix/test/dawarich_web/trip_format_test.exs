defmodule DawarichWeb.TripFormatTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.{LocalizedDate, NumberFormat, TripFormat}

  test "card distances round half away from zero in the user's unit; no distance is 0" do
    assert TripFormat.distance(999_500, 1000) == 1000
    assert TripFormat.distance(1499, 1000) == 1
    assert TripFormat.distance(16_093, 1609.34) == 10
    assert TripFormat.distance(nil, 1000) == 0
  end

  test "number_with_precision rounds half-up on the shortest decimal and keeps one decimal" do
    assert NumberFormat.with_precision_one("en", 12.25) == "12.3"
    assert NumberFormat.with_precision_one("en", 1.15) == "1.2"
    assert NumberFormat.with_precision_one("en", 12.0) == "12.0"
    assert NumberFormat.with_precision_one("en", 1.0e21) == "1000000000000000000000.0"
  end

  test "a day under one unit reads '< 1'" do
    assert TripFormat.day_distance("en", 999.0, 1000) == "< 1"
    assert TripFormat.day_distance("en", 1112.3, 1000) == "1.1"
  end

  test "durations join Rails' pluralized parts, or say 0 hours" do
    assert TripFormat.duration("en", [{"days", 1}, {"hours", 22}]) == "1 day, 22 hours"
    assert TripFormat.duration("en", []) == "0 hours"
  end

  test "short_month_day_weekday names the weekday from the locale" do
    assert LocalizedDate.l("en", ~D[2026-05-10], "short_month_day_weekday") == "May 10, Sunday"
    assert LocalizedDate.l("de", ~D[2026-05-10], "short_month_day_weekday") == "10. Mai, Sonntag"
  end
end
