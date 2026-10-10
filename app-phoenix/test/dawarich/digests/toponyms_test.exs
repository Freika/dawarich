defmodule Dawarich.Digests.ToponymsTest do
  use ExUnit.Case, async: true

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.Toponyms

  test "first visits exclude country-only entries and combine equal city names across countries" do
    kase = DigestFixtures.case!("berlin_monthly")
    stats = history(kase)
    first = Toponyms.first_visits(stats, 2025, 3)
    assert first == hd(kase["expected"]["rows"])["first_time_visits"]
    refute "Country only" in first["countries"]

    assert Toponyms.city_minutes(current(kase)) ==
             hd(kase["expected"]["rows"])["time_spent_by_location"]["cities"]

    assert Enum.count(Toponyms.city_minutes(current(kase)), &(&1["name"] == "Springfield")) == 1

    malformed = DigestFixtures.case!("malformed_minutes_monthly")

    assert_raise Toponyms.InvalidInteger, malformed["expected"]["error"]["message"], fn ->
      Toponyms.city_minutes(current(malformed))
    end
  end

  test "yearly toponyms preserve encounter ties and sort each city's names" do
    for id <- [
          "ranked_locations_yearly",
          "berlin_yearly",
          "country_shapes_yearly",
          "malformed_json_yearly"
        ] do
      kase = DigestFixtures.case!(id)
      assert Toponyms.aggregate(current(kase)) == hd(kase["expected"]["rows"])["toponyms"], id
    end
  end

  test "first visits retain a valid city with no enclosing country" do
    for {kind, month} <- [{"monthly", 3}, {"yearly", nil}] do
      kase = DigestFixtures.case!("berlin_#{kind}")
      result = Toponyms.first_visits(history(kase), 2025, month)
      assert "Orphan city" in result["cities"]
      refute nil in result["countries"]
      assert result == hd(kase["expected"]["rows"])["first_time_visits"]
    end
  end

  defp history(kase),
    do: Enum.filter(kase["input"]["stats"], &(&1["user_id"] == kase["call"]["user_id"]))

  defp current(kase) do
    call = kase["call"]

    history(kase)
    |> Enum.filter(
      &(&1["year"] == call["year"] and (is_nil(call["month"]) or &1["month"] == call["month"]))
    )
    |> Enum.sort_by(& &1["month"])
  end
end
