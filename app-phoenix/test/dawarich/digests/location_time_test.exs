defmodule Dawarich.Digests.LocationTimeTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Context, LocationTime, Period, Queries}

  test "monthly local dates and yearly UTC dates produce their respective Rails minutes" do
    for id <-
          ~w(berlin_monthly berlin_yearly southern_monthly southern_yearly missing_zone_monthly
                 january_monthly january_yearly lite_partial_yearly lite_inherited_yearly) do
      assert_recorded(id)
    end
  end

  test "independent rounded spans preserve top ten order and non-1440 totals" do
    for id <- ~w(ranked_locations_monthly ranked_locations_yearly) do
      result = assert_recorded(id)
      assert result["total_country_minutes"] == 1441
      assert length(result["countries"]) == 10
      assert hd(result["countries"]) == %{"name" => "Country 10", "minutes" => 131}
      assert List.last(result["countries"]) == %{"name" => "Country 1", "minutes" => 131}
    end
  end

  defp assert_recorded(id) do
    kase = DigestFixtures.case!(id)

    {:error, {:recorded, result}} =
      ScratchRepo.transaction(fn ->
        DigestFixtures.load!(ScratchRepo, kase)
        call = kase["call"]
        context = Context.load!(ScratchRepo, call["user_id"], DigestFixtures.options(kase))

        {period, stats} =
          if call["month"] do
            period = Period.monthly(ScratchRepo, context, call["year"], call["month"])
            {period, [Queries.monthly(ScratchRepo, period.context, call["year"], call["month"])]}
          else
            period = Period.yearly(ScratchRepo, context, call["year"])
            {period, Queries.yearly(ScratchRepo, period.context, call["year"])}
          end

        result = LocationTime.calculate(ScratchRepo, period.context, period, stats)
        assert result == hd(kase["expected"]["rows"])["time_spent_by_location"], id
        ScratchRepo.rollback({:recorded, result})
      end)

    result
  end
end
