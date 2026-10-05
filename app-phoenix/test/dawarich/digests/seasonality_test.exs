defmodule Dawarich.Digests.SeasonalityTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Context, Seasonality}

  test "raw persisted Sydney is southern but alias missing and invalid zones stay northern" do
    for id <-
          ~w(southern_yearly southern_alias_yearly missing_zone_yearly invalid_zone_yearly blank_zone_yearly) do
      assert {:error, :recorded} =
               ScratchRepo.transaction(fn ->
                 kase = DigestFixtures.case!(id)
                 DigestFixtures.load!(ScratchRepo, kase)
                 options = DigestFixtures.options(kase)
                 env = Map.put(options[:env], "TIME_ZONE", "Australia/Sydney")
                 context = Context.load!(ScratchRepo, 14101, Keyword.put(options, :env, env))
                 actual = Seasonality.calculate(ScratchRepo, context, 2025)
                 assert actual == hd(kase["expected"]["rows"])["travel_patterns"]["seasonality"]
                 ScratchRepo.rollback(:recorded)
               end)
    end
  end

  test "seasonality uses scoped months and preserves independent integer rounding" do
    kase = DigestFixtures.case!("lite_partial_yearly")
    DigestFixtures.load!(ScratchRepo, kase)
    context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))

    assert Seasonality.calculate(ScratchRepo, context, 2025) ==
             hd(kase["expected"]["rows"])["travel_patterns"]["seasonality"]

    ScratchRepo.query!("UPDATE public.stats SET distance = 0 WHERE user_id = 14101")

    assert Seasonality.calculate(ScratchRepo, context, 2025) == %{
             "winter" => 0,
             "spring" => 0,
             "summer" => 0,
             "fall" => 0
           }

    context = %{context | stat_cutoff: nil, restricted?: false}

    ScratchRepo.query!(
      "UPDATE public.stats SET distance = 1 WHERE user_id = 14101 AND year = 2025 AND month IN (1, 9, 10)"
    )

    assert Seasonality.calculate(ScratchRepo, context, 2025) == %{
             "winter" => 33,
             "spring" => 0,
             "summer" => 0,
             "fall" => 67
           }

    ScratchRepo.query!("UPDATE public.stats SET month = 3 WHERE id = 14302")

    assert Seasonality.calculate(ScratchRepo, context, 2025) == %{
             "winter" => 33,
             "spring" => 33,
             "summer" => 0,
             "fall" => 33
           }
  end
end
