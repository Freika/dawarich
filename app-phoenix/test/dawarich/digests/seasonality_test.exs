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

  test "all 27 persisted southern aliases use pinned Rails northern seasons for January distance" do
    kase = DigestFixtures.case!("southern_yearly")
    DigestFixtures.load!(ScratchRepo, kase)

    ScratchRepo.query!(
      "UPDATE public.stats SET year = 2025, distance = CASE WHEN id = 14301 THEN 1000 ELSE 0 END"
    )

    for zone <- ~w(
      Africa/Blantyre Africa/Brazzaville Africa/Bujumbura
      Africa/Dar_es_Salaam Africa/Gaborone Africa/Harare
      Africa/Kigali Africa/Kinshasa Africa/Luanda
      Africa/Lubumbashi Africa/Lusaka Africa/Maseru
      Africa/Mbabane Antarctica/DumontDUrville Antarctica/McMurdo
      Antarctica/Syowa Atlantic/St_Helena Indian/Antananarivo
      Indian/Christmas Indian/Cocos Indian/Comoro
      Indian/Kerguelen Indian/Mahe Indian/Mayotte
      Indian/Reunion Pacific/Funafuti Pacific/Wallis
    ) do
      ScratchRepo.query!(
        "UPDATE public.users SET settings = jsonb_set(settings::jsonb, '{timezone}', to_jsonb($1::text)) WHERE id = 14101",
        [zone]
      )

      context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
      assert context.raw_zone == zone

      assert Seasonality.calculate(ScratchRepo, context, 2025) == %{
               "winter" => 100,
               "spring" => 0,
               "summer" => 0,
               "fall" => 0
             },
             zone
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
