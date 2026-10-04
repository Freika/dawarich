defmodule Dawarich.Stats.CalculateMonthTest do
  use Dawarich.JobsCase

  alias Dawarich.StatsFixtures, as: F
  alias Dawarich.Stats.{CalculateMonth, GeocodedDays}

  @now ~N[2026-10-03 12:00:00.000000]
  @t0 1_790_000_000

  setup do: F.reset!()

  for id <-
        ~w(berlin_march_dst reset_keeps_flight margin_only_creates_month unchanged_row_untouched h3_fallback) do
    @id id
    test "calculates the month Rails calculated: #{id}" do
      kase = F.case!(@id)
      F.load!(kase)
      %{"user_id" => user_id, "year" => year, "month" => month} = kase["call"]

      assert CalculateMonth.call(ScratchRepo, user_id, year, month, now: @now, clock: @t0) == :ok
      assert F.stat(user_id, year, month) == kase["expected"]["stat"]
    end
  end

  test "a month without points and without statistics stays absent and records nothing" do
    F.user!(94, %{})
    assert CalculateMonth.call(ScratchRepo, 94, 2024, 3, now: @now) == :ok
    assert F.stat(94, 2024, 3) == nil
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  test "records the Rails cache invalidation for the year in the calculation's transaction" do
    F.user!(92, %{"timezone" => "Etc/UTC"})
    F.point!(9201, 92, F.ts(2024, 3, 5))
    assert CalculateMonth.call(ScratchRepo, 92, 2024, 3, now: @now) == :ok

    assert rows("SELECT kind, payload FROM phoenix.rails_commands") == [
             ["stats.caches_invalidated", %{"user_id" => 92, "year" => 2024, "scope" => "all"}]
           ]
  end

  test "acknowledges the pending days inside the local month and leaves a boundary day pending" do
    F.user!(91, %{"timezone" => "Asia/Tokyo"})
    F.point!(9101, 91, F.ts(2015, 1, 12))
    GeocodedDays.mark(ScratchRepo, 91, F.ts(2015, 1, 12), @t0)
    GeocodedDays.mark(ScratchRepo, 91, F.ts(2014, 12, 31, 23, 30), @t0)

    assert CalculateMonth.call(ScratchRepo, 91, 2015, 1, now: @now, clock: @t0) == :ok
    assert rows("SELECT member FROM phoenix.stats_geocoded_days") == [["91:2014-12-31"]]
  end

  test "a failure rolls the month back and notifies in the user's locale" do
    F.user!(93, %{"timezone" => "Etc/UTC", "locale" => "de"})
    F.point!(9301, 93, F.ts(2024, 3, 5))
    GeocodedDays.mark(ScratchRepo, 93, F.ts(2024, 3, 5), @t0)
    boom = fn _repo, _user, _year, _month -> raise "boom" end

    ExUnit.CaptureLog.capture_log(fn ->
      assert {:error, %RuntimeError{message: "boom"}} =
               CalculateMonth.call(ScratchRepo, 93, 2024, 3,
                 now: @now,
                 clock: @t0,
                 hexagons: boom
               )
    end)

    assert F.stat(93, 2024, 3) == nil
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.stats_geocoded_days") == [[1]]

    assert [[2, "Statistikaktualisierung fehlgeschlagen", content]] =
             rows("SELECT kind, title, content FROM notifications WHERE user_id = 93")

    assert String.starts_with?(content, "boom, Stacktrace: ")
  end

  test "a failure without notify_on_failure leaves no notification" do
    F.user!(96, %{"timezone" => "Etc/UTC"})
    F.point!(9601, 96, F.ts(2024, 3, 5))
    boom = fn _repo, _user, _year, _month -> raise "boom" end

    ExUnit.CaptureLog.capture_log(fn ->
      assert {:error, _} =
               CalculateMonth.call(ScratchRepo, 96, 2024, 3,
                 now: @now,
                 notify: false,
                 hexagons: boom
               )
    end)

    assert rows("SELECT count(*) FROM notifications WHERE user_id = 96") == [[0]]
  end

  test "a missing or deleted user is skipped" do
    F.user!(95, %{}, %{"deleted_at" => "2026-10-01T00:00:00"})
    assert CalculateMonth.call(ScratchRepo, 95, 2024, 3, now: @now) == :missing
    assert CalculateMonth.call(ScratchRepo, 9_999, 2024, 3, now: @now) == :missing
  end
end
