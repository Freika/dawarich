defmodule Dawarich.Digests.TimeOfDayTest do
  use Dawarich.DataCase, async: true, group: :digest_fixture_ids
  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Context, Period, TimeOfDay}

  test "four six-hour slots include boundary and anomaly points and default invalid zones to UTC" do
    for id <-
          ~w(berlin_monthly berlin_yearly southern_monthly southern_yearly missing_zone_monthly
                 invalid_zone_yearly blank_zone_yearly lite_partial_yearly) do
      assert {:error, :recorded} =
               ScratchRepo.transaction(fn ->
                 kase = DigestFixtures.case!(id)
                 DigestFixtures.load!(ScratchRepo, kase)
                 context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
                 call = kase["call"]

                 period =
                   if call["month"],
                     do: Period.monthly(ScratchRepo, context, call["year"], call["month"]),
                     else: Period.yearly(ScratchRepo, context, call["year"])

                 assert TimeOfDay.calculate(ScratchRepo, context, period) ==
                          hd(kase["expected"]["rows"])["travel_patterns"]["time_of_day"]

                 ScratchRepo.rollback(:recorded)
               end)
    end

    kase = DigestFixtures.case!("berlin_yearly")
    DigestFixtures.load!(ScratchRepo, kase)
    context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
    period = Period.yearly(ScratchRepo, context, 2025)
    ScratchRepo.query!("DELETE FROM public.points")

    assert TimeOfDay.calculate(ScratchRepo, context, period) == %{
             "night" => 0,
             "morning" => 0,
             "afternoon" => 0,
             "evening" => 0
           }

    row = hd(kase["input"]["points"])

    for {id, timestamp} <- [
          {15001, period.first - 1},
          {15002, period.first},
          {15003, period.last},
          {15004, period.last + 1}
        ] do
      DigestFixtures.row!(ScratchRepo, "points", %{
        row
        | "id" => id,
          "timestamp" => timestamp,
          "anomaly" => id == 15002
      })
    end

    assert TimeOfDay.calculate(ScratchRepo, context, period) == %{
             "night" => 50,
             "morning" => 0,
             "afternoon" => 0,
             "evening" => 50
           }
  end
end
