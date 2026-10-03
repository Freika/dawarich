defmodule Dawarich.VisitsApi.MergeBulkTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.VisitsApi.{BulkUpdate, Merge}

  @now ~U[2026-10-03 12:00:00.000000Z]
  @stamp ~N[2026-09-01 12:00:00.000000]

  setup do
    rows("TRUNCATE places,visits CASCADE")

    ScratchRepo.insert_all("users", [
      %{
        id: 953_001,
        email: "a4rest-merge@example.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    for id <- [953_201, 953_202] do
      rows(
        "INSERT INTO places (id,user_id,name,latitude,longitude,created_at,updated_at) VALUES ($1,953001,'Synthetic',52.52,13.405,$2,$2)",
        [id, @stamp]
      )
    end

    for {id, place, name, status, deleted, offset} <- [
          {953_301, 953_201, "First", 0, nil, 0},
          {953_302, 953_202, " first ", 1, nil, 3600},
          {953_303, 953_201, "Hidden", 1, @stamp, 7200},
          {953_304, 953_201, "Declined", 2, nil, 10800}
        ] do
      ScratchRepo.insert_all("visits", [
        %{
          id: id,
          user_id: 953_001,
          place_id: place,
          name: name,
          status: status,
          deleted_at: deleted,
          duration: 60,
          started_at: NaiveDateTime.add(@stamp, offset),
          ended_at: NaiveDateTime.add(@stamp, offset + 3659),
          created_at: @stamp,
          updated_at: @stamp
        }
      ])
    end

    for id <- [953_301, 953_302] do
      rows(
        "INSERT INTO points (user_id,visit_id,timestamp,lonlat,created_at,updated_at) VALUES (953001,$1::bigint,$1::bigint,ST_SetSRID(ST_MakePoint(13.405,52.52),4326),$2,$2)",
        [id, @stamp]
      )

      ScratchRepo.insert_all("place_visits", [
        %{visit_id: id, place_id: 953_202, created_at: @stamp, updated_at: @stamp}
      ])
    end

    ScratchRepo.insert_all("notes", [
      %{
        user_id: 953_001,
        attachable_type: "Visit",
        attachable_id: 953_302,
        body: "Synthetic",
        noted_at: @stamp,
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    :ok
  end

  test "merge preserves earliest base and reassigns points before dependent deletes" do
    assert {:ok, visit} = merge([953_302, 953_301])
    assert visit.id == 953_301
    assert visit.status == 1
    assert rows("SELECT visit_id FROM points ORDER BY id") == [[953_301], [953_301]]
    assert rows("SELECT visit_id FROM place_visits") == [[953_301]]
    assert rows("SELECT id FROM notes") == []
    assert rows("SELECT id FROM visits ORDER BY id") == [[953_301], [953_303], [953_304]]
    assert rows("SELECT id FROM places ORDER BY id") == [[953_201], [953_202]]

    assert Enum.any?(commands(), fn [kind, payload] ->
             kind == "places_delete_if_orphan" && payload["place_ids"] == [953_202]
           end)

    assert {:error, 422, _} = merge([953_301])
    assert {:error, 404, _} = merge([953_301, 953_301])
    assert {:error, 404, _} = merge([953_301, 953_303])
  end

  test "merge uses rounded span and case-insensitive first-name dedup" do
    assert {:ok, visit} = merge([953_302, 953_301])
    assert visit.duration == 121
    assert visit.name == "First"
    assert visit.ended_at == ~N[2026-09-01 14:00:59.000000]
  end

  test "bulk decline counts selected active rows and queues distinct orphan places" do
    assert {:ok, 2} =
             BulkUpdate.call(953_001, [953_301, 953_302, 953_303, 953_304, 959_999], "declined")

    assert rows("SELECT status,updated_at FROM visits ORDER BY id") == [
             [2, @stamp],
             [2, @stamp],
             [1, @stamp],
             [2, @stamp]
           ]

    assert commands() == [
             [
               "places_delete_if_orphan",
               %{"user_id" => 953_001, "place_ids" => [953_201, 953_202]}
             ]
           ]

    assert {:error, 422, _} = BulkUpdate.call(953_001, [], "confirmed")
    assert {:error, 422, _} = BulkUpdate.call(953_001, [953_303], "confirmed")
    assert {:error, 422, _} = BulkUpdate.call(953_001, [953_303], "invalid")
  end

  test "merge failure rolls every row and private effect back without replay" do
    before = snapshot()

    rows(
      "ALTER TABLE phoenix.rails_commands ADD CONSTRAINT a4rest_reject_orphan CHECK (kind != 'places_delete_if_orphan') NOT VALID"
    )

    try do
      assert_raise Postgrex.Error, fn -> merge([953_302, 953_301]) end
      assert snapshot() == before
      assert commands() == []
    after
      rows("ALTER TABLE phoenix.rails_commands DROP CONSTRAINT a4rest_reject_orphan")
    end
  end

  defp merge(ids), do: Merge.call(953_001, ids, "UTC", @now)
  defp commands, do: rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

  defp snapshot,
    do:
      for(
        table <- ~w(visits points notes place_visits),
        do: rows("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      )
end
