defmodule Dawarich.Digests.RefreshDBTest do
  use ExUnit.Case, async: false
  alias Dawarich.{DigestRefresh, Repo}

  @fields ~w(distance flight_distance toponyms monthly_distances time_spent_by_location first_time_visits year_over_year all_time_stats travel_patterns)
  @corpus Path.expand("../../fixtures/insights/b3-corpus.json", __DIR__)
  @now ~U[2026-06-15 10:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    corpus = Jason.decode!(File.read!(@corpus))
    seed(corpus)
    reader = Enum.find(corpus["users"], &(&1["email"] == "e2e-stats@dawarich.test"))
    %{corpus: corpus, id: reader["id"]}
  end

  for year <- [2023, 2024] do
    test "actual persisted yearly calculator #{year} matches Rails", %{corpus: corpus, id: id} do
      year = unquote(year)

      expected =
        Enum.find(corpus["digests"], &(&1["year"] == year and &1["period_type"] == "yearly"))

      actual = DigestRefresh.year(id, year, now: @now, self_hosted: false)
      assert Map.take(actual, @fields) == Map.take(expected, @fields)

      assert [[1]] ==
               Repo.query!(
                 "SELECT COUNT(*) FROM digests WHERE user_id=$1 AND year=$2 AND period_type=1",
                 [id, year],
                 log: false
               ).rows

      assert [[0]] ==
               Repo.query!("SELECT COUNT(*) FROM digests WHERE user_id<>$1", [id], log: false).rows

      assert Ecto.UUID.cast(actual["sharing_uuid"]) != :error
    end
  end

  for {year, month} <- [{2023, 7}, {2024, 3}, {2024, 4}] do
    test "actual persisted monthly calculator #{year}-#{month} matches Rails", %{
      corpus: corpus,
      id: id
    } do
      {year, month} = unquote({year, month})

      expected =
        Enum.find(
          corpus["digests"],
          &(&1["year"] == year and &1["month"] == month and &1["period_type"] == "monthly")
        )

      actual = DigestRefresh.month(id, year, month, now: @now, self_hosted: false)
      assert Map.take(actual, @fields) == Map.take(expected, @fields)

      assert [[1]] ==
               Repo.query!(
                 "SELECT COUNT(*) FROM digests WHERE user_id=$1 AND year=$2 AND month=$3 AND period_type=0",
                 [id, year, month],
                 log: false
               ).rows

      assert [[0]] ==
               Repo.query!("SELECT COUNT(*) FROM digests WHERE user_id<>$1", [id], log: false).rows
    end
  end

  test "no stats produces no persisted digest and refresh preserves existing row metadata", %{
    id: id
  } do
    assert DigestRefresh.year(id, 2020, now: @now, self_hosted: false) == nil
    assert DigestRefresh.month(id, 2024, 2, now: @now, self_hosted: false) == nil
    first = DigestRefresh.year(id, 2024, now: @now, self_hosted: false)

    Repo.query!(
      "UPDATE digests SET flight_distance=777, sharing_settings=$2 WHERE id=$1",
      [first["id"], %{"enabled" => true}],
      log: false
    )

    next = DigestRefresh.year(id, 2024, now: DateTime.add(@now, 1), self_hosted: false)

    assert Map.take(next, ~w(id sharing_uuid created_at)) ==
             Map.take(first, ~w(id sharing_uuid created_at))

    assert next["flight_distance"] == 777
    assert next["sharing_settings"] == %{"enabled" => true}
  end

  test "existing yearly mixed-month duplicates keep oldest id and metadata", %{id: id} do
    first_id = 910_000_001

    for {digest_id, month} <- [{first_id, 5}, {first_id + 1, 7}] do
      Repo.query!(
        "INSERT INTO digests(id,user_id,year,month,period_type,flight_distance,sharing_settings,created_at,updated_at) VALUES($1,$2,2024,$3,1,777,$4,$5,$5)",
        [digest_id, id, month, %{"enabled" => true}, DateTime.to_naive(@now)],
        log: false
      )
    end

    result = DigestRefresh.year(id, 2024, now: @now, self_hosted: false)
    assert result["id"] == first_id
    assert result["month"] == 5
    assert result["flight_distance"] == 777
    assert result["sharing_settings"] == %{"enabled" => true}

    assert Repo.query!("SELECT id FROM digests WHERE user_id=$1 ORDER BY id", [id], log: false).rows ==
             [[first_id]]
  end

  test "actual unique index collision retries without poisoning the request transaction", %{
    id: id
  } do
    Process.put(:a10_digest_collision, false)

    {:ok, result} =
      Repo.transaction(fn ->
        DigestRefresh.year(id, 2024,
          now: @now,
          self_hosted: false,
          repo: Dawarich.Test.A10DigestCollisionRepo
        )
      end)

    assert Process.get(:a10_digest_collision)
    assert result["distance"] == 50_072

    assert [[1]] ==
             Repo.query!(
               "SELECT COUNT(*) FROM digests WHERE user_id=$1 AND year=2024 AND period_type=1",
               [id],
               log: false
             ).rows

    assert [[1]] == Repo.query!("SELECT 1", [], log: false).rows
  end

  test "actual persisted track gaps and walking segment equal Rails activity projection", %{
    id: id
  } do
    fixture =
      Jason.decode!(
        File.read!(Path.expand("../../fixtures/insights/activity-gaps.json", __DIR__))
      )

    for [track, first, last] <- fixture["tracks"] do
      Repo.query!(
        "INSERT INTO tracks(id,user_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,$2,$3,$4,ST_GeomFromText('LINESTRING(13.4 52.5,13.4 52.5)',4326),$5,$5)",
        [track, id, timestamp(first), timestamp(last), DateTime.to_naive(@now)],
        log: false
      )
    end

    for [track, _mode, duration] <- fixture["durations"] do
      Repo.query!(
        "INSERT INTO track_segments(track_id,transportation_mode,duration,created_at,updated_at) VALUES($1,2,$2,$3,$3)",
        [track, duration, DateTime.to_naive(@now)],
        log: false
      )
    end

    for {[track, time, lat, lon], n} <- Enum.with_index(fixture["points"]) do
      Repo.query!(
        "INSERT INTO points(id,user_id,track_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,$4,ST_SetSRID(ST_MakePoint($5,$6),4326),$7,$7)",
        [930_000_000 + n, id, track, time, lon, lat, DateTime.to_naive(@now)],
        log: false
      )
    end

    result = DigestRefresh.year(id, 2024, now: @now, self_hosted: false)
    assert result["travel_patterns"]["activity_breakdown"] == fixture["expected"]
    ordered = Jason.decode!(result["_rails_json"]["travel_patterns"], objects: :ordered_objects)
    %Jason.OrderedObject{values: pairs} = ordered["activity_breakdown"]
    assert Enum.map(pairs, &elem(&1, 0)) == ~w(walking stationary flying)
  end

  defp seed(corpus) do
    for user <- corpus["users"] do
      Repo.query!(
        "INSERT INTO users(id,email,status,plan,settings,active_until,created_at,updated_at) VALUES($1,$2,1,1,$3,$4,$5,$5)",
        [
          user["id"],
          user["email"],
          user["settings"],
          timestamp(user["active_until"]),
          DateTime.to_naive(@now)
        ],
        log: false
      )
    end

    for stat <- corpus["stats"] do
      Repo.query!(
        """
        INSERT INTO stats(id,user_id,year,month,distance,flight_distance,toponyms,daily_distance,created_at,updated_at)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
        """,
        Enum.map(
          ~w(id user_id year month distance flight_distance toponyms daily_distance),
          &stat[&1]
        ) ++
          [timestamp(stat["created_at"]), timestamp(stat["updated_at"])],
        log: false
      )
    end

    for [id, user, time, country, city, lon, lat] <- corpus["points"] do
      Repo.query!(
        """
        INSERT INTO points(id,user_id,timestamp,country_name,city,lonlat,created_at,updated_at)
        VALUES($1,$2,$3,$4,$5,ST_SetSRID(ST_MakePoint($6,$7),4326),$8,$8)
        """,
        [id, user, time, country, city, lon, lat, DateTime.to_naive(@now)],
        log: false
      )
    end
  end

  defp timestamp(value) do
    {:ok, time, _} = DateTime.from_iso8601(value)
    DateTime.to_naive(time)
  end
end
