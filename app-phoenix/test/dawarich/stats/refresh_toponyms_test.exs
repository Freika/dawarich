defmodule Dawarich.Stats.RefreshToponymsTest do
  use Dawarich.JobsCase

  alias Dawarich.StatsFixtures, as: F
  alias Dawarich.Stats.{Accounts, RefreshToponyms}

  @now ~N[2026-10-03 12:00:00.000000]
  @settings %{"timezone" => "Etc/UTC", "min_minutes_spent_in_city" => 0}
  @leipzig %{"city" => "Leipzig", "country_name" => "Germany"}

  setup do: F.reset!()

  test "refreshes the month Rails refreshed and preserves the sweep watermark" do
    kase = F.case!("refresh_toponyms_tokyo")
    F.load!(kase)
    account = Accounts.find(ScratchRepo, 12_107)

    assert RefreshToponyms.call(ScratchRepo, account, 2015, 1, false, now: @now) ==
             kase["expected"]["result"]

    assert F.stat(12_107, 2015, 1) == kase["expected"]["stat"]
    assert F.swept_at(12_107) == kase["expected"]["stats_swept_at"]
  end

  test "changes only toponyms and updated_at" do
    F.user!(51, @settings)

    F.stat!(5101, 51, 2014, 6, %{
      "distance" => 123,
      "daily_distance" => %{"15" => 123},
      "h3_hex_ids" => [["hex", 12]],
      "calculation_version" => 1
    })

    F.point!(5102, 51, F.ts(2014, 6, 15, 12), @leipzig)
    before = untouched(5101)

    assert RefreshToponyms.call(ScratchRepo, Accounts.find(ScratchRepo, 51), 2014, 6, false,
             now: @now
           )

    assert untouched(5101) == before

    assert [[[%{"country" => "Germany", "cities" => [%{"city" => "Leipzig"}]}], @now]] =
             rows("SELECT toponyms, updated_at FROM stats WHERE id = 5101")
  end

  test "does not rewrite an unchanged result and asks Rails to invalidate only when changed or told to" do
    F.user!(52, @settings)
    F.stat!(5201, 52, 2014, 6)
    F.point!(5202, 52, F.ts(2014, 6, 15, 12), @leipzig)
    account = Accounts.find(ScratchRepo, 52)

    assert RefreshToponyms.call(ScratchRepo, account, 2014, 6, false, now: @now)

    assert RefreshToponyms.call(ScratchRepo, account, 2014, 6, false,
             now: ~N[2026-10-03 13:00:00.000000]
           )

    assert rows("SELECT updated_at FROM stats WHERE id = 5201") == [[@now]]
    assert length(invalidations()) == 1

    assert RefreshToponyms.call(ScratchRepo, account, 2014, 6, true,
             now: ~N[2026-10-03 13:00:00.000000]
           )

    assert invalidations() == [
             %{"user_id" => 52, "year" => 2014, "scope" => "toponyms"},
             %{"user_id" => 52, "year" => 2014, "scope" => "toponyms"}
           ]
  end

  test "repairs a partial nonempty result" do
    F.user!(53, @settings)
    F.stat!(5301, 53, 2014, 6, %{"toponyms" => [%{"country" => "France", "cities" => []}]})
    F.point!(5302, 53, F.ts(2014, 6, 15, 12), @leipzig)

    assert RefreshToponyms.call(ScratchRepo, Accounts.find(ScratchRepo, 53), 2014, 6, false,
             now: @now
           )

    assert [[[%{"country" => "Germany"}]]] = rows("SELECT toponyms FROM stats WHERE id = 5301")
  end

  test "a month without statistics answers whether it has no points and creates no row" do
    F.user!(54, @settings)
    F.point!(5401, 54, F.ts(2015, 1, 15))
    account = Accounts.find(ScratchRepo, 54)

    refute RefreshToponyms.call(ScratchRepo, account, 2015, 1, false, now: @now)
    assert RefreshToponyms.call(ScratchRepo, account, 2015, 2, false, now: @now)
    assert rows("SELECT count(*) FROM stats") == [[0]]
  end

  test "streams a month larger than one fetch batch" do
    F.user!(55, @settings)
    F.stat!(5501, 55, 2014, 6)

    ScratchRepo.query!(
      "INSERT INTO points (id, user_id, timestamp, lonlat, city, country_name, velocity, anomaly, created_at, updated_at) " <>
        "SELECT 550000 + g, 55, $1::int + g, 'SRID=4326;POINT(12.3731 51.3397)'::geography, 'Leipzig', 'Germany', '0', false, " <>
        "'2026-10-01', '2026-10-01' FROM generate_series(1, 4001) AS g",
      [F.ts(2014, 6, 1)]
    )

    assert RefreshToponyms.call(ScratchRepo, Accounts.find(ScratchRepo, 55), 2014, 6, false,
             now: @now
           )

    assert [[[%{"cities" => [%{"points" => 4001}]}]]] =
             rows("SELECT toponyms FROM stats WHERE id = 5501")
  end

  test "keeps a newer completed sweep" do
    F.user!(56, @settings, %{"stats_swept_at" => "2026-10-03T11:00:00"})
    F.stat!(5601, 56, 2014, 6)
    F.point!(5602, 56, F.ts(2014, 6, 15, 12), @leipzig)

    assert RefreshToponyms.call(ScratchRepo, Accounts.find(ScratchRepo, 56), 2014, 6, false,
             now: @now
           )

    assert F.swept_at(56) == "2026-10-03T11:00:00"
  end

  defp untouched(id),
    do:
      rows(
        "SELECT distance, daily_distance, h3_hex_ids, calculation_version, sharing_uuid, created_at FROM stats WHERE id = $1",
        [id]
      )

  defp invalidations,
    do:
      for(
        [payload] <-
          rows(
            "SELECT payload FROM phoenix.rails_commands WHERE kind = 'stats.caches_invalidated' ORDER BY id"
          ),
        do: payload
      )
end
