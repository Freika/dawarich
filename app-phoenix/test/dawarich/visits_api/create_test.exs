defmodule Dawarich.VisitsApi.CreateTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.VisitsApi.Create

  @now ~U[2026-10-03 12:00:00.000000Z]
  @stamp ~N[2026-09-01 12:00:00.000000]

  setup do
    rows("TRUNCATE places,visits,tags,taggings CASCADE")
    rows("DELETE FROM instance_settings")

    ScratchRepo.insert_all("users", [
      %{
        id: 953_001,
        email: "a4rest-create@example.invalid",
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

    for {id, owner, demo} <- [
          {953_201, 953_001, true},
          {953_202, 953_002, false},
          {953_203, 953_001, false}
        ] do
      rows(
        "INSERT INTO places (id,user_id,name,latitude,longitude,lonlat,demo,created_at,updated_at) VALUES ($1,$2,'Nearby',52.52,13.405,ST_SetSRID(ST_MakePoint(13.405,52.52),4326),$3,$4,$4)",
        [id, owner, demo, @stamp]
      )
    end

    ScratchRepo.insert_all("visits", [
      %{
        id: 953_301,
        user_id: 953_001,
        place_id: 953_201,
        name: "Nearby",
        status: 1,
        duration: 60,
        started_at: @stamp,
        ended_at: ~N[2026-09-01 13:00:00],
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    ScratchRepo.insert_all("tags", [
      %{
        id: 953_701,
        user_id: 953_001,
        name: "Synthetic",
        demo: true,
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    ScratchRepo.insert_all("taggings", [
      %{
        tag_id: 953_701,
        taggable_type: "Place",
        taggable_id: 953_201,
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    :ok
  end

  test "create uses a nearby visited own place and ignores submitted place_id" do
    assert {:ok, visit} = create(%{"place_id" => 953_202, "area_id" => 953_999})

    assert rows("SELECT place_id,area_id,status FROM visits WHERE id=$1", [visit.id]) == [
             [953_201, nil, 1]
           ]

    assert rows("SELECT demo,updated_at FROM places WHERE id=953201") == [
             [false, DateTime.to_naive(@now)]
           ]

    assert rows("SELECT demo FROM tags WHERE id=953701") == [[false]]
    assert rows("SELECT COUNT(*) FROM places") == [[3]]

    assert commands() == [
             [
               "visit_months_changed",
               %{"user_id" => 953_001, "started_at" => ["2026-09-02T12:00:00.000000Z"]}
             ]
           ]
  end

  test "confirmed duplicate revives tombstone but suggested duplicate does not" do
    rows("UPDATE visits SET deleted_at=$1,status=0 WHERE id=953301", [@stamp])

    assert {:ok, tombstone} =
             create(%{
               "started_at" => "2026-09-01T12:00:00Z",
               "ended_at" => "2026-09-01T13:00:00Z",
               "status" => "suggested"
             })

    assert tombstone.duplicate
    assert tombstone.deleted_at == @stamp
    assert commands() == []

    assert {:ok, revived} =
             create(%{
               "started_at" => "2026-09-01T12:00:00Z",
               "ended_at" => "2026-09-01T14:00:00Z",
               "name" => "Revived"
             })

    assert revived.id == 953_301
    assert revived.duplicate
    assert revived.deleted_at == nil

    assert rows("SELECT status,duration,name FROM visits WHERE id=953301") == [
             [1, 120, "Revived"]
           ]
  end

  test "conflicting duplicate fails without leaking newly created place" do
    assert {:error, 422, "A visit already exists at this place and time"} =
             create(%{"started_at" => "2026-09-01T12:00:00Z", "name" => "Conflict"})

    assert rows("SELECT COUNT(*) FROM visits") == [[1]]
    assert rows("SELECT COUNT(*) FROM places") == [[3]]
    assert commands() == []
    assert {:error, 422, _} = create(%{"latitude" => 40, "longitude" => 10, "name" => ""})
    assert rows("SELECT COUNT(*) FROM places") == [[3]]

    assert {:error, 422, "Failed to create visit: invalid coordinates"} =
             create(%{"latitude" => "bad"})

    assert {:error, 422, "Failed to create visit: coordinates out of range"} =
             create(%{"latitude" => 91})

    assert {:error, 422, "Failed to create visit: invalid timestamps"} =
             create(%{"started_at" => nil})

    assert {:error, 422, "Failed to create visit: ended_at must be after started_at"} =
             create(%{"ended_at" => "2026-09-01T12:00:00Z"})

    assert {:replay, _} = create(%{"started_at" => "September"})
    assert commands() == []
  end

  test "duration truncates minutes and suggested new place emits name effect" do
    ScratchRepo.insert_all("instance_settings", [
      %{
        key: "photon_api_host",
        value: "synthetic.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    assert {:ok, visit} =
             create(%{
               "latitude" => 40,
               "longitude" => 10,
               "name" => "Suggested place",
               "status" => "suggested",
               "ended_at" => "2026-09-02T12:01:59Z"
             })

    assert rows("SELECT duration,status FROM visits WHERE id=$1", [visit.id]) == [[1, 0]]
    [[place]] = rows("SELECT place_id FROM visits WHERE id=$1", [visit.id])
    assert rows("SELECT source,name_locked_at FROM places WHERE id=$1", [place]) == [[0, nil]]

    assert commands() == [
             [
               "visit_months_changed",
               %{"user_id" => 953_001, "started_at" => ["2026-09-02T12:00:00.000000Z"]}
             ],
             ["place_name_fetch", %{"user_id" => 953_001, "place_id" => place}]
           ]
  end

  defp create(changes),
    do:
      Create.call(
        953_001,
        Map.merge(
          %{
            "latitude" => 52.52,
            "longitude" => 13.405,
            "started_at" => "2026-09-02T12:00:00Z",
            "ended_at" => "2026-09-02T13:00:00Z"
          },
          changes
        ),
        "UTC",
        @now
      )

  defp commands, do: rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
end
