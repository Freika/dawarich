defmodule Dawarich.Digests.ComparisonTest do
  use Dawarich.DataCase, async: true, group: :digest_fixture_ids
  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Comparison, Context, Queries}

  test "January compares with December and zero previous distance omits only the percentage" do
    for id <- ~w(january_monthly previous_zero_monthly berlin_monthly berlin_yearly) do
      kase = DigestFixtures.case!(id)
      call = kase["call"]

      actual =
        if call["month"],
          do: Comparison.monthly(history(kase), call["year"], call["month"]),
          else: Comparison.yearly(history(kase), call["year"])

      assert actual == hd(kase["expected"]["rows"])["year_over_year"]
    end

    assert Comparison.monthly([], 2025, 1) == %{}
    assert Comparison.yearly([], 2025) == %{}
  end

  test "all-time locations are unrestricted while distance uses the scoped decimal string" do
    kase = DigestFixtures.case!("lite_partial_yearly")
    DigestFixtures.load!(ScratchRepo, kase)
    context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))

    actual =
      Comparison.all_time(
        Queries.history(ScratchRepo, context),
        Queries.distance(ScratchRepo, context)
      )

    assert actual == hd(kase["expected"]["rows"])["all_time_stats"]
    assert actual["total_distance"] == "25000"
  end

  test "all-time cities include a valid city with no enclosing country" do
    kase = DigestFixtures.case!("berlin_monthly")
    stats = history(kase)

    without_orphan =
      Enum.map(stats, fn stat ->
        Map.update!(stat, "toponyms", &Enum.reject(&1, fn top -> is_nil(top["country"]) end))
      end)

    actual = Comparison.all_time(stats, "39500")
    reduced = Comparison.all_time(without_orphan, "39500")
    assert actual["total_cities"] == reduced["total_cities"] + 1
    assert actual["total_countries"] == reduced["total_countries"]
    assert actual == hd(kase["expected"]["rows"])["all_time_stats"]
  end

  defp history(kase),
    do: Enum.filter(kase["input"]["stats"], &(&1["user_id"] == kase["call"]["user_id"]))
end
