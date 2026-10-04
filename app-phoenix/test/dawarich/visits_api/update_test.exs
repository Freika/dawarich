defmodule Dawarich.VisitsApi.UpdateTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.VisitsApi.Update

  @now ~U[2026-10-03 12:00:00.000000Z]
  @stamp ~N[2026-09-01 12:00:00.000000]

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(places areas visits))

    ScratchRepo.insert_all("users", [
      %{
        id: 953_001,
        email: "a4rest-update@example.invalid",
        created_at: @stamp,
        updated_at: @stamp
      },
      %{
        id: 953_002,
        email: "a4rest-other@example.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    for {id, owner} <- [{953_201, 953_001}, {953_202, 953_002}, {953_203, 953_002}] do
      rows(
        "INSERT INTO places (id,user_id,name,latitude,longitude,created_at,updated_at) VALUES ($1,$2,$3,52.52,13.405,$4,$4)",
        [id, owner, "Place #{id}", @stamp]
      )
    end

    for {id, owner} <- [{953_101, 953_001}, {953_102, 953_002}] do
      ScratchRepo.insert_all("areas", [
        %{
          id: id,
          user_id: owner,
          name: "Area #{id}",
          latitude: 53.0,
          longitude: 14.0,
          radius: 100,
          created_at: @stamp,
          updated_at: @stamp
        }
      ])
    end

    ScratchRepo.insert_all("visits", [
      %{
        id: 953_301,
        user_id: 953_001,
        place_id: 953_201,
        name: "Before",
        status: 0,
        duration: 60,
        started_at: @stamp,
        ended_at: ~N[2026-09-01 13:00:00],
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    ScratchRepo.insert_all("place_visits", [
      %{visit_id: 953_301, place_id: 953_202, created_at: @stamp, updated_at: @stamp}
    ])

    rows(
      "INSERT INTO points (user_id,visit_id,timestamp,lonlat,created_at,updated_at) VALUES (953001,953301,1788264000,ST_SetSRID(ST_MakePoint(13.405,52.52),4326),$1,$1)",
      [@stamp]
    )

    :ok
  end

  @tag mutation: "M-review-visit-dirty"
  test "name PATCH preserves an interleaved decline and does not emit its orphan effect" do
    rows("UPDATE visits SET status=1 WHERE id=953301")
    handler = "a4rest-visit-dirty"

    :ok =
      :telemetry.attach(
        handler,
        [:dawarich, :scratch_repo, :query],
        &__MODULE__.interleave/4,
        {self(), handler}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:ok, visit} = update(%{"name" => "Edited name"})
    assert_received :decline_committed
    assert visit.name == "Edited name"
    assert rows("SELECT name,status FROM visits WHERE id=953301") == [["Edited name", 2]]
    refute Enum.any?(commands(), fn [kind, _] -> kind == "places_delete_if_orphan" end)
  end

  def interleave(_event, _measurements, %{query: query}, {parent, handler}) do
    if self() == parent &&
         String.starts_with?(query, "SELECT id,user_id,place_id,area_id,name,status") do
      :telemetry.detach(handler)
      [[primary]] = rows("SELECT pg_backend_pid()")

      Task.async(fn ->
        ScratchRepo.checkout(fn ->
          assert rows("SELECT pg_backend_pid()") != [[primary]]
          rows("UPDATE visits SET status=2 WHERE id=953301")
        end)
      end)
      |> Task.await()

      send(parent, :decline_committed)
    end
  end

  test "editing suggested visit confirms unless explicit status supplied" do
    assert {:ok, visit} = update(%{"name" => "Edited", "latitude" => 0, "longitude" => 0})
    assert visit.status == 1
    assert visit.duration == 60

    assert rows("SELECT latitude::float,longitude::float FROM places WHERE id=953201") == [
             [52.52, 13.405]
           ]

    rows("UPDATE visits SET status=0 WHERE id=953301")
    assert {:ok, visit} = update(%{"status" => "declined"})
    assert visit.status == 2
    assert Enum.any?(commands(), fn [kind, _] -> kind == "places_delete_if_orphan" end)
  end

  test "place and area assignment enforce ownership with name precedence" do
    assert {:error, 422, "Invalid place"} = update(%{"place_id" => 953_203})
    assert {:error, 422, "Invalid area"} = update(%{"area_id" => 953_102})
    assert commands() == []
    assert {:ok, visit} = update(%{"place_id" => 953_202, "area_id" => 953_101})
    assert visit.name == "Place 953202"
    assert visit.area_id == 953_101
    assert {:ok, visit} = update(%{"place_id" => 953_201, "name" => "Caller"})
    assert visit.name == "Caller"
    assert {:ok, visit} = update(%{"area_id" => 953_101})
    assert visit.name == "Area 953101"
    assert Update.call(953_002, 953_301, %{"name" => "Foreign"}, "UTC", @now) == :not_found
  end

  test "destroy tombstones and leaves point visit_id intact" do
    assert {:ok, 204} = Update.destroy(953_001, 953_301, "UTC", @now)
    assert rows("SELECT deleted_at FROM visits WHERE id=953301") == [[DateTime.to_naive(@now)]]
    assert rows("SELECT visit_id FROM points") == [[953_301]]
    assert rows("SELECT visit_id FROM place_visits") == [[953_301]]
    assert Update.destroy(953_001, 953_301, "UTC", @now) == :not_found
    assert Update.destroy(953_002, 953_301, "UTC", @now) == :not_found

    assert commands() == [
             ["places_delete_if_orphan", %{"user_id" => 953_001, "place_ids" => [953_201]}],
             [
               "visit_months_changed",
               %{"user_id" => 953_001, "started_at" => ["2026-09-01T12:00:00.000000Z"]}
             ]
           ]
  end

  test "moving months invalidates both months and cleans old place" do
    assert {:ok, visit} =
             update(%{
               "place_id" => 953_202,
               "started_at" => "2026-10-01T12:00:00Z",
               "ended_at" => "2026-10-01T13:00:00Z"
             })

    assert visit.duration == 60

    assert commands() == [
             ["places_delete_if_orphan", %{"user_id" => 953_001, "place_ids" => [953_201]}],
             [
               "visit_months_changed",
               %{
                 "user_id" => 953_001,
                 "started_at" => ["2026-10-01T12:00:00.000000Z", "2026-09-01T12:00:00.000000Z"]
               }
             ]
           ]

    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(phoenix.rails_commands))
    rows("UPDATE visits SET demo=true WHERE id=953301")
    assert {:ok, _} = update(%{"status" => "declined"})
    assert commands() == []
  end

  defp update(attrs), do: Update.call(953_001, 953_301, attrs, "UTC", @now)
  defp commands, do: rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
end
