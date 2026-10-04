defmodule Dawarich.Digests.CalculateYearTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{CalculateYear, Context}

  @fields ~w(distance toponyms monthly_distances time_spent_by_location first_time_visits year_over_year all_time_stats travel_patterns)

  test "yearly attributes fill twelve string months and never assign flight distance" do
    for kase <- DigestFixtures.all(),
        kase["call"]["kind"] == "yearly",
        kase["expected"]["error"] == nil,
        kase["expected"]["rows"] != [] do
      assert {:error, :recorded} =
               ScratchRepo.transaction(fn ->
                 DigestFixtures.load!(ScratchRepo, kase)
                 context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
                 attrs = CalculateYear.attributes(ScratchRepo, context, kase["call"]["year"])
                 assert attrs == Map.take(hd(kase["expected"]["rows"]), @fields), kase["id"]
                 refute Map.has_key?(attrs, "flight_distance")
                 assert map_size(attrs["monthly_distances"]) == 12

                 assert Enum.all?(attrs["monthly_distances"], fn {month, distance} ->
                          is_binary(month) and is_binary(distance)
                        end)

                 ScratchRepo.rollback(:recorded)
               end)
    end
  end

  test "an empty scoped year returns nil despite older unrestricted stats" do
    kase = DigestFixtures.case!("old_data_yearly")
    DigestFixtures.load!(ScratchRepo, kase)
    context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
    assert CalculateYear.attributes(ScratchRepo, context, 2024) == nil
    assert CalculateYear.attributes(ScratchRepo, context, 2025) == nil
    ScratchRepo.query!("DELETE FROM public.stats WHERE user_id = 14101")
    assert CalculateYear.attributes(ScratchRepo, context, 2025) == nil
  end
end
