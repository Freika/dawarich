defmodule Dawarich.Test.StatsSeeds do
  @moduledoc false

  alias Dawarich.Repo

  def stat!(user_id, attrs) do
    stamp = NaiveDateTime.utc_now(:second)

    row =
      Map.merge(
        %{
          user_id: user_id,
          distance: 0,
          daily_distance: [],
          toponyms: [],
          sharing_settings: %{},
          created_at: stamp,
          updated_at: stamp
        },
        attrs
      )

    Dawarich.Test.SeedIds.insert_all!(Repo, "stats", [row])
    row
  end

  def digest!(user_id, attrs) do
    stamp = NaiveDateTime.utc_now(:second)

    Dawarich.Test.SeedIds.insert_all!(Repo, "digests", [
      Map.merge(
        %{user_id: user_id, period_type: 1, distance: 0, created_at: stamp, updated_at: stamp},
        attrs
      )
    ])
  end

  def toponym(country, cities),
    do: %{"country" => country, "cities" => Enum.map(cities, &%{"city" => &1})}

  def point!(user_id, attrs) do
    stamp = NaiveDateTime.utc_now(:second)

    Dawarich.Test.SeedIds.insert_all!(Repo, "points", [
      Map.merge(%{user_id: user_id, created_at: stamp, updated_at: stamp}, attrs)
    ])
  end

  def geocoding!(store_geodata \\ true) do
    stamp = NaiveDateTime.utc_now(:second)

    rows = [
      %{
        key: "photon_api_host",
        value: "photon.test.example.com",
        created_at: stamp,
        updated_at: stamp
      }
    ]

    rows =
      if store_geodata,
        do: rows,
        else: [%{key: "store_geodata", value: false, created_at: stamp, updated_at: stamp} | rows]

    Dawarich.Test.SeedIds.insert_all!(Repo, "instance_settings", rows)
  end
end
