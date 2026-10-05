defmodule Dawarich.Stats.TrackedMonthsTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Stats.TrackedMonths

  test "matches source tracked months in database zone and source ordering" do
    kase = Fixtures.case!("full")
    Fixtures.load!(ScratchRepo, kase)
    user = hd(kase["input"]["users"])
    point = hd(kase["input"]["points"])

    Fixtures.row!(
      ScratchRepo,
      "users",
      Map.merge(user, %{"id" => 170_102, "email" => "foreign@example.invalid"})
    )

    Fixtures.row!(
      ScratchRepo,
      "points",
      Map.merge(point, %{"id" => 170_230, "user_id" => 170_102, "timestamp" => 0})
    )

    {:ok, :ok} =
      ScratchRepo.transaction(fn ->
        rows("SELECT set_config('TimeZone', $1, true)", [kase["database_zone"]])

        for zone <- ~w(Europe/Berlin Asia/Tokyo Unknown/Zone) do
          rows(
            "UPDATE users SET settings = settings || jsonb_build_object('timezone', $1::text) WHERE id = $2",
            [zone, 170_101]
          )

          assert TrackedMonths.call(ScratchRepo, 170_101) == expected(kase)
        end

        assert TrackedMonths.call(ScratchRepo, -1) == []
        :ok
      end)

    {:ok, months} =
      ScratchRepo.transaction(fn ->
        rows("SELECT set_config('TimeZone', 'Asia/Tokyo', true)")
        TrackedMonths.call(ScratchRepo, 170_101)
      end)

    assert months == [%{year: 2026, months: ["Jan"]}, %{year: 2025, months: ["Jan", "Mar"]}]
  end

  test "reads current months when the Rails day cache is stale" do
    kase = Fixtures.case!("full_stale")
    Fixtures.load!(ScratchRepo, kase)

    assert expected(kase) == [
             %{year: 2025, months: ~w(Jan Mar Dec)},
             %{year: 2024, months: ["Dec"]}
           ]

    {:ok, :ok} =
      ScratchRepo.transaction(fn ->
        rows("SELECT set_config('TimeZone', $1, true)", [kase["database_zone"]])

        assert TrackedMonths.call(ScratchRepo, 170_101) == [
                 %{year: 2025, months: ~w(Jan Mar Jun Dec)},
                 %{year: 2024, months: ["Dec"]}
               ]

        rows("UPDATE points SET timestamp = $1 WHERE id = $2", [1_754_049_600, 170_220])

        assert TrackedMonths.call(ScratchRepo, 170_101) == [
                 %{year: 2025, months: ~w(Jan Mar Aug Dec)},
                 %{year: 2024, months: ["Dec"]}
               ]

        :ok
      end)
  end

  defp expected(kase),
    do: Enum.map(kase["expected"]["result"], &%{year: &1["year"], months: &1["months"]})
end
