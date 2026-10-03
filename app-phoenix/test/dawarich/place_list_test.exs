defmodule Dawarich.PlaceListTest do
  use ExUnit.Case, async: false

  alias Dawarich.{PlaceList, Repo}
  alias Dawarich.Test.FrameSeeds, as: S

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    saved = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")
    on_exit(fn -> if saved, do: System.put_env("TIME_ZONE", saved) end)
    %{user: user!(8411)}
  end

  defp user!(id, settings \\ %{"timezone" => "Europe/Berlin"}),
    do: S.user!(id, settings, %{email: "a84-#{id}@example.invalid", api_key: "a84-k-#{id}"})

  defp set!(id, assignments, params),
    do: Repo.query!("UPDATE places SET #{assignments} WHERE id = $1", [id | params])

  defp ids({:ok, %{entries: entries}}), do: Enum.map(entries, & &1.id)

  defp fill!(user, count) do
    for id <- (841_100 + count)..841_101//-1, do: S.place!(user.id, id, "Ort #{id}")
  end

  test "pages hold 20 places in id order, whatever order the rows were written in", %{user: user} do
    fill!(user, 23)

    first = PlaceList.load(user, nil)
    assert ids(first) == Enum.to_list(841_101..841_120)
    assert {:ok, %{total_pages: 2}} = first
    assert ids(PlaceList.load(user, "2")) == [841_121, 841_122, 841_123]
  end

  test "page values follow Kaminari's to_i and clamp at 1", %{user: user} do
    fill!(user, 23)
    first = PlaceList.load(user, nil)
    second = PlaceList.load(user, "2")

    for page <- ["0", "-1", ""], do: assert(PlaceList.load(user, page) == first)
    for page <- ["2abc", "2 x"], do: assert(PlaceList.load(user, page) == second)
  end

  test "a legacy place without lonlat shows its decimal columns", %{user: user} do
    S.place!(user.id, 841_201, "Alt", legacy: true, offset: {0.0, 0.001})

    assert {:ok, %{entries: [%{lat: 51.3407, lon: 12.3731}]}} = PlaceList.load(user, nil)
  end

  test "coordinates are the stored doubles", %{user: user} do
    S.place!(user.id, 841_301, "Genau")

    set!(841_301, "lonlat = ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography", [
      12.373468123456789,
      51.33970012345678
    ])

    assert {:ok, %{entries: [entry]}} = PlaceList.load(user, nil)
    assert {entry.lat, entry.lon} == {51.33970012345678, 12.373468123456789}
  end

  test "created_at carries the zone offset; UTC users get Z", %{user: user} do
    S.place!(user.id, 841_401, "Winter")
    S.place!(user.id, 841_402, "Sommer")
    set!(841_401, "created_at = $2", [~N[2026-01-05 09:30:00]])
    set!(841_402, "created_at = $2", [~N[2026-07-15 09:30:00]])

    assert {:ok, %{entries: [winter, summer]}} = PlaceList.load(user, nil)
    assert winter.created == %{local: ~N[2026-01-05 10:30:00.000000], offset: 3600, utc: false}
    assert summer.created == %{local: ~N[2026-07-15 11:30:00.000000], offset: 7200, utc: false}

    utc = user!(8412, %{"timezone" => "UTC"})
    S.place!(utc.id, 841_403, "UTC")
    set!(841_403, "created_at = $2", [~N[2026-02-03 23:59:30]])

    assert {:ok, %{entries: [entry]}} = PlaceList.load(utc, nil)
    assert entry.created == %{local: ~N[2026-02-03 23:59:30.000000], offset: 0, utc: true}
  end

  test "settings Rails rejects hand back", %{user: user} do
    S.place!(user.id, 841_501, "Ort")

    assert PlaceList.load(%{user | settings: []}, nil) == :rails
    assert PlaceList.load(%{user | settings: %{"timezone" => 5}}, nil) == :rails
    assert PlaceList.load(%{user | settings: %{"timezone" => "Mars/Phobos"}}, nil) == :rails

    for settings <- [%{"timezone" => ""}, %{}, %{"timezone" => "Berlin"}, nil],
        do: assert({:ok, %{entries: [_]}} = PlaceList.load(%{user | settings: settings}, nil))
  end

  test "an empty page needs no zone", %{user: user} do
    mars = %{user | settings: %{"timezone" => "Mars/Phobos"}}
    assert PlaceList.load(mars, nil) == {:ok, %{entries: [], total_pages: 0}}

    fill!(user, 3)
    assert {:ok, %{entries: []}} = PlaceList.load(mars, "9")
  end

  test "a page beyond 10^15 hands back", %{user: user} do
    assert PlaceList.load(user, "1000000000000001") == :rails
    assert {:ok, %{entries: []}} = PlaceList.load(user, "1000000000000000")
  end

  test "another user's places never appear", %{user: user} do
    other = user!(8419)
    S.place!(other.id, 841_901, "Fremd")
    S.place!(user.id, 841_902, "Eigen")

    assert {:ok, %{entries: [%{id: 841_902, name: "Eigen"}], total_pages: 1}} =
             PlaceList.load(user, nil)
  end
end
