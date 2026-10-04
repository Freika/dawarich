defmodule Dawarich.Digests.CalculateMonthTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{CalculateMonth, Context}

  @fields ~w(distance flight_distance toponyms monthly_distances time_spent_by_location first_time_visits year_over_year all_time_stats travel_patterns)

  test "monthly attributes copy flight distance and string-key daily values exactly" do
    for kase <- DigestFixtures.all(),
        kase["call"]["kind"] == "monthly",
        kase["expected"]["error"] == nil,
        kase["expected"]["rows"] != [],
        not kase["legacy_duplicates"] do
      assert {:error, :recorded} =
               ScratchRepo.transaction(fn ->
                 DigestFixtures.load!(ScratchRepo, kase)
                 context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
                 call = kase["call"]

                 assert CalculateMonth.attributes(
                          ScratchRepo,
                          context,
                          call["year"],
                          call["month"]
                        ) == Map.take(hd(kase["expected"]["rows"]), @fields),
                        kase["id"]

                 ScratchRepo.rollback(:recorded)
               end)
    end

    assert {:error, :recorded} =
             ScratchRepo.transaction(fn ->
               kase = DigestFixtures.case!("malformed_daily_monthly")
               DigestFixtures.load!(ScratchRepo, kase)
               context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))

               assert_raise CalculateMonth.InvalidDaily,
                            kase["expected"]["error"]["message"],
                            fn ->
                              CalculateMonth.attributes(ScratchRepo, context, 2025, 3)
                            end

               ScratchRepo.rollback(:recorded)
             end)
  end

  test "missing monthly stat returns nil without consulting point metrics" do
    kase = DigestFixtures.case!("no_data_monthly")
    DigestFixtures.load!(ScratchRepo, kase)
    context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
    context = %{context | effective_zone: "Invalid/Zone", user_zone: nil}
    assert CalculateMonth.attributes(ScratchRepo, context, 2025, 13) == nil
  end
end
