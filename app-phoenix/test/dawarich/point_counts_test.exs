defmodule Dawarich.Stats.PointCountsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import Dawarich.Test.StatsSeeds

  alias Dawarich.Stats.PointCounts
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    RailsUser.insert!(%{id: 5601, email: "a5s-pc@dawarich.test"})
    RailsUser.insert!(%{id: 5602, email: "a5s-pc2@dawarich.test"})
    at = ~N[2024-03-05 09:00:00]
    point!(5601, %{reverse_geocoded_at: at, city: "Berlin", country_name: "Germany"})
    point!(5601, %{reverse_geocoded_at: at})
    point!(5601, %{reverse_geocoded_at: at, country: "Germany"})
    point!(5601, %{})
    point!(5602, %{reverse_geocoded_at: at})
    :ok
  end

  test "counts the user's reverse-geocoded points, and those without data only with store_geodata" do
    now = ~U[2026-09-26 12:00:00Z]
    assert PointCounts.fetch(5601, true, now) == %{geocoded: 3, without_data: 1}
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(phoenix.stats_point_counts))
    assert PointCounts.fetch(5601, false, now) == %{geocoded: 3, without_data: nil}
  end

  test "a row younger than a day wins over new points; an older one is recomputed and replaced" do
    now = ~U[2026-09-26 12:00:00Z]

    ScratchRepo.query!("INSERT INTO phoenix.stats_point_counts VALUES (5601, 40, 2, $1)", [
      DateTime.add(now, -3600)
    ])

    assert PointCounts.fetch(5601, true, now) == %{geocoded: 40, without_data: 2}

    ScratchRepo.query!("UPDATE phoenix.stats_point_counts SET computed_at = $1", [
      DateTime.add(now, -86_401)
    ])

    assert PointCounts.fetch(5601, true, now) == %{geocoded: 3, without_data: 1}

    assert rows(
             "SELECT geocoded, computed_at = $1 FROM phoenix.stats_point_counts WHERE user_id = 5601",
             [now]
           ) == [[3, true]]
  end
end
