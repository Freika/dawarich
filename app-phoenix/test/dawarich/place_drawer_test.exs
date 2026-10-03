defmodule Dawarich.PlaceDrawerTest do
  use ExUnit.Case, async: false

  alias Dawarich.{PlaceDrawer, Repo}
  alias Dawarich.Test.FrameSeeds, as: S

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    saved = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")
    on_exit(fn -> if saved, do: System.put_env("TIME_ZONE", saved) end)
    user = user!(8441)
    S.place!(user.id, 844_101, "Café")
    %{user: user}
  end

  defp user!(id, settings \\ %{"timezone" => "Europe/Berlin"}),
    do: S.user!(id, settings, %{email: "a84-#{id}@example.invalid", api_key: "a84-k-#{id}"})

  defp set!(table, id, assignments, params),
    do: Repo.query!("UPDATE #{table} SET #{assignments} WHERE id = $1", [id | params])

  defp visit!(user_id, id, started, minutes, attrs \\ %{}),
    do:
      S.visit!(
        user_id,
        id,
        Map.merge(
          %{
            place_id: 844_101,
            name: "Besuch #{id}",
            started_at: started,
            ended_at: NaiveDateTime.add(started, minutes * 60),
            duration: minutes
          },
          attrs
        )
      )

  defp names({:ok, drawer}, key), do: Enum.map(drawer[key], & &1.name)

  defp tied_tagging!(user_id, id, tag_id, name) do
    at = ~N[2026-09-01 10:00:00]

    Repo.insert_all("tags", [
      %{id: tag_id, user_id: user_id, name: name, created_at: at, updated_at: at}
    ])

    Repo.insert_all("taggings", [
      %{
        id: id,
        tag_id: tag_id,
        taggable_type: "Place",
        taggable_id: 844_101,
        created_at: at,
        updated_at: at
      }
    ])
  end

  test "the drawer holds the place, active counts, tags and the five latest active visits", %{
    user: user
  } do
    set!(
      "places",
      844_101,
      "source = 1, note = $2, name_locked_at = now(), city = $3, country = $4",
      [
        "Notiz",
        "Leipzig",
        "  "
      ]
    )

    S.tag!(user.id, 84_412, "Work", 844_101, ~N[2026-09-02 10:00:00])
    S.tag!(user.id, 84_411, "Coffee", 844_101, ~N[2026-09-01 10:00:00])
    set!("tags", 84_411, "icon = $2, color = $3", ["☕", "#aa33cc"])
    set!("tags", 84_412, "icon = NULL, color = NULL", [])

    for {n, minutes} <- Enum.zip(1..6, [10, 20, 30, 40, 50, 60]),
        do:
          visit!(
            user.id,
            84_400 + n,
            NaiveDateTime.add(~N[2026-09-01 08:00:00], n * 86_400),
            minutes
          )

    set!("visits", 84_403, "status = 0", [])
    visit!(user.id, 84_407, ~N[2026-09-20 08:00:00], 600, %{status: 2})

    assert {:ok, drawer} = PlaceDrawer.load(user, 844_101)

    assert Map.drop(drawer, [:tags, :visits]) == %{
             id: 844_101,
             name: "Café",
             note: "Notiz",
             city: "Leipzig",
             country: "  ",
             source: "photon",
             locked: true,
             visit_count: 6,
             total_minutes: 210
           }

    assert drawer.tags == [
             %{name: "Coffee", icon: "☕", color: "#aa33cc"},
             %{name: "Work", icon: nil, color: nil}
           ]

    assert Enum.map(drawer.visits, & &1.name) ==
             Enum.map(6..2//-1, &"Besuch #{84_400 + &1}")

    assert hd(drawer.visits).duration == 60
  end

  test "soft-deleted visits are excluded everywhere", %{user: user} do
    visit!(user.id, 84_421, ~N[2026-09-01 08:00:00], 30)
    visit!(user.id, 84_422, ~N[2026-09-02 08:00:00], 600, %{deleted_at: ~N[2026-09-03 08:00:00]})

    assert {:ok, %{visit_count: 1, total_minutes: 30} = drawer} = PlaceDrawer.load(user, 844_101)
    assert names({:ok, drawer}, :visits) == ["Besuch 84421"]
  end

  test "ties order by id", %{user: user} do
    other = user!(8442)
    tied_tagging!(user.id, 84_433, 84_434, "Drei")
    tied_tagging!(user.id, 84_432, 84_435, "Zwei")
    visit!(user.id, 84_432, ~N[2026-09-01 08:00:00], 30)
    visit!(other.id, 84_433, ~N[2026-09-01 08:00:00], 30)

    assert names(PlaceDrawer.load(user, 844_101), :tags) == ["Zwei", "Drei"]
    assert names(PlaceDrawer.load(user, 844_101), :visits) == ["Besuch 84433", "Besuch 84432"]
  end

  test "a tie across the fifth visit keeps the higher id", %{user: user} do
    other = user!(8445)
    visit!(user.id, 84_462, ~N[2026-09-01 08:00:00], 30)
    visit!(other.id, 84_463, ~N[2026-09-01 08:00:00], 30)

    for n <- 1..4,
        do:
          visit!(user.id, 84_470 + n, NaiveDateTime.add(~N[2026-09-01 08:00:00], n * 86_400), 30)

    assert names(PlaceDrawer.load(user, 844_101), :visits) ==
             ["Besuch 84474", "Besuch 84473", "Besuch 84472", "Besuch 84471", "Besuch 84463"]
  end

  test "visit times are local to the user's zone", %{user: user} do
    visit!(user.id, 84_441, ~N[2026-03-28 07:15:00], 45)
    visit!(user.id, 84_442, ~N[2026-03-30 07:15:00], 135)

    assert {:ok, %{visits: [after_switch, before_switch]}} = PlaceDrawer.load(user, 844_101)

    assert {before_switch.started, before_switch.ended} ==
             {~N[2026-03-28 08:15:00], ~N[2026-03-28 09:00:00]}

    assert {after_switch.started, after_switch.ended} ==
             {~N[2026-03-30 09:15:00], ~N[2026-03-30 11:30:00]}

    utc = user!(8443, %{"timezone" => "UTC"})
    S.place!(utc.id, 844_301, "UTC")
    visit!(utc.id, 84_443, ~N[2026-09-30 23:50:00], 25, %{place_id: 844_301})

    assert {:ok, %{visits: [late]}} = PlaceDrawer.load(utc, 844_301)
    assert {late.started, late.ended} == {~N[2026-09-30 23:50:00], ~N[2026-10-01 00:15:00]}
  end

  test "a blank zone shows Rails' TIME_ZONE default, a missing one UTC", %{user: user} do
    visit!(user.id, 84_451, ~N[2026-03-28 07:15:00], 45)
    started = fn settings -> PlaceDrawer.load(%{user | settings: settings}, 844_101) end

    assert {:ok, %{visits: [%{started: ~N[2026-03-28 08:15:00]}]}} =
             started.(%{"timezone" => ""})

    assert {:ok, %{visits: [%{started: ~N[2026-03-28 07:15:00]}]}} = started.(%{})
  end

  test "a missing or another user's place hands back", %{user: user} do
    other = user!(8444)
    S.place!(other.id, 844_401, "Fremd")

    assert PlaceDrawer.load(user, 844_199) == :rails
    assert PlaceDrawer.load(user, 844_401) == :rails
  end

  test "an unknown source hands back", %{user: user} do
    set!("places", 844_101, "source = NULL", [])
    assert PlaceDrawer.load(user, 844_101) == :rails
    set!("places", 844_101, "source = 7", [])
    assert PlaceDrawer.load(user, 844_101) == :rails

    for {source, name} <- [{0, "manual"}, {1, "photon"}, {2, "gpx_waypoint"}] do
      set!("places", 844_101, "source = $2", [source])
      assert {:ok, %{source: ^name}} = PlaceDrawer.load(user, 844_101)
    end
  end

  test "settings Rails rejects hand back", %{user: user} do
    assert PlaceDrawer.load(%{user | settings: []}, 844_101) == :rails
    assert PlaceDrawer.load(%{user | settings: %{"timezone" => 5}}, 844_101) == :rails
    assert PlaceDrawer.load(%{user | settings: %{"timezone" => "Mars/Phobos"}}, 844_101) == :rails

    for settings <- [%{"timezone" => ""}, %{}, %{"timezone" => "Berlin"}, nil],
        do: assert({:ok, _} = PlaceDrawer.load(%{user | settings: settings}, 844_101))
  end
end
