defmodule Dawarich.Digests.ActivityTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Activity, Context, Period}

  test "start-time-selected tracks include nil-mode duration in the denominator" do
    for id <-
          ~w(nil_mode_monthly nil_mode_yearly track_bounds_monthly track_bounds_yearly lite_partial_yearly) do
      recorded(id, fn context, period, kase ->
        assert Activity.calculate(ScratchRepo, context, period) == expected(kase)
      end)
    end

    recorded("berlin_monthly", fn context, period, kase ->
      ScratchRepo.query!("DELETE FROM public.points WHERE track_id IS NOT NULL")

      ScratchRepo.query!(
        "UPDATE public.tracks SET start_at = $1, end_at = $1::timestamp + interval '1 minute' WHERE id = 14402",
        [period.until]
      )

      assert Activity.calculate(ScratchRepo, context, period) == %{
               "walking" => %{"duration" => 2400, "percentage" => 100}
             }

      ScratchRepo.query!(
        "UPDATE public.tracks SET start_at = $1::timestamp - interval '1 microsecond', end_at = $1::timestamp + interval '1 minute' WHERE id = 14402",
        [period.from]
      )

      assert Activity.calculate(ScratchRepo, context, period) == %{
               "walking" => %{"duration" => 600, "percentage" => 100}
             }

      for {mode, index} <-
            Enum.with_index(
              ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)
            ) do
        ScratchRepo.query!("UPDATE public.track_segments SET transportation_mode = $1", [index])

        assert Activity.calculate(ScratchRepo, context, period) == %{
                 mode => %{"duration" => 600, "percentage" => 100}
               }
      end

      ScratchRepo.query!("DELETE FROM public.track_segments")
      assert Activity.calculate(ScratchRepo, context, period) == %{}
      assert expected(kase)["walking"]["duration"] == 2400
    end)
  end

  test "stationary and flight gaps honor all exact thresholds and missing endpoints" do
    for index <- 0..14 do
      recorded("gap_#{index}_monthly", fn context, period, kase ->
        gap = kase["expected"]["gap"]
        assert Activity.classify(gap["seconds"], gap["distance_km"]) == gap["classification"]

        %{rows: rows} =
          ScratchRepo.query!(
            "SELECT public.ST_Y(lonlat::public.geometry), public.ST_X(lonlat::public.geometry) FROM public.points WHERE id IN (14260,14261) ORDER BY id"
          )

        [first, last] = Enum.map(rows, &List.to_tuple/1)
        assert Activity.distance_km(first, last) == gap["geocoder_distance_km"]
        assert Activity.calculate(ScratchRepo, context, period) == expected(kase)
      end)
    end

    recorded("missing_endpoint_monthly", fn context, period, kase ->
      assert Activity.calculate(ScratchRepo, context, period) == expected(kase)
    end)
  end

  defp recorded(id, fun) do
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

               fun.(context, period, kase)
               ScratchRepo.rollback(:recorded)
             end)
  end

  defp expected(kase), do: hd(kase["expected"]["rows"])["travel_patterns"]["activity_breakdown"]
end
