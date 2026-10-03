defmodule Dawarich.SharedApi.TripTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.SharedApi.Trip
  alias Dawarich.Test.TripsSeeds

  test "trip metadata omits distance unless literal show_stats is true" do
    previous = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "Europe/Berlin")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

    owner = user!(%{settings: %{"maps" => %{"distance_unit" => "mi"}}})
    other = user!()

    TripsSeeds.trip!(%{
      id: 951_101,
      user_id: owner,
      name: "Synthetic shared trip",
      distance: 123_456,
      started_at: ~N[2026-03-29 00:00:00],
      ended_at: ~N[2026-03-29 01:00:00]
    })

    link = %{type: "trip", user_id: owner, resource_id: 951_101, settings: %{}}

    fields = [
      {"name", "Synthetic shared trip"},
      {"started_at", "2026-03-29T01:00:00.000+01:00"},
      {"ended_at", "2026-03-29T03:00:00.000+02:00"}
    ]

    for flag <- [nil, false, "true", 1],
        do:
          assert(
            Trip.show(%{link | settings: %{"show_stats" => flag}}) == {:ok, {:object, fields}}
          )

    assert Trip.show(%{link | settings: %{"show_stats" => true}}) ==
             {:ok, {:object, fields ++ [{"distance", 77}, {"distance_unit", "mi"}]}}

    Repo.query!("UPDATE trips SET distance = 803866 WHERE id = 951101")

    assert Trip.show(%{link | settings: %{"show_stats" => true}}) ==
             {:ok, {:object, fields ++ [{"distance", 500}, {"distance_unit", "mi"}]}}

    Repo.query!("UPDATE trips SET distance = 123456 WHERE id = 951101")

    Repo.query!("UPDATE users SET settings = $1 WHERE id = $2", [
      %{"maps" => %{"distance_unit" => "km"}},
      owner
    ])

    assert Trip.show(%{link | settings: %{"show_stats" => true}}) ==
             {:ok, {:object, fields ++ [{"distance", 123}, {"distance_unit", "km"}]}}

    Repo.query!("UPDATE trips SET distance = NULL WHERE id = $1", [951_101])
    assert Trip.show(%{link | settings: %{"show_stats" => true}}) == {:ok, {:object, fields}}
    assert Trip.show(%{link | user_id: other}) == {:error, 410, "gone"}
    assert Trip.show(%{link | resource_id: 959_999}) == {:error, 410, "gone"}
  end
end
