defmodule Dawarich.Visits.WebMergeTest do
  use Dawarich.JobsCase
  alias Dawarich.Visits.WebMerge
  @now ~U[2026-10-03 10:00:00Z]
  @old ~N[2026-10-03 08:00:00.000000]
  @stamp ~N[2026-10-03 10:00:00.000000]

  setup do
    rows(
      "TRUNCATE places, tags, taggings, visits, place_visits, areas, notes RESTART IDENTITY CASCADE"
    )

    ScratchRepo.insert_all("users", [
      %{
        id: 8930,
        email: "a8-merge@dawarich.test",
        encrypted_password: "synthetic",
        settings: %{},
        created_at: @old,
        updated_at: @old
      }
    ])

    for {id, owner} <- [{893_010, 8930}, {893_011, 8930}] do
      ScratchRepo.insert_all("places", [
        %{
          id: id,
          user_id: owner,
          name: "Place #{id}",
          latitude: Decimal.new("51"),
          longitude: Decimal.new("12"),
          created_at: @old,
          updated_at: @old
        }
      ])
    end

    visit!(893_002, %{
      name: "Park",
      started_at: ~N[2026-10-03 08:40:00],
      ended_at: ~N[2026-10-03 09:50:30],
      place_id: 893_011
    })

    visit!(893_001, %{name: " Cafe ", place_id: 893_010})

    %{
      user: %{id: 8930, settings: %{"timezone" => "Europe/Berlin"}},
      context: %{now: @now, self_hosted: true}
    }
  end

  defp visit!(id, attrs) do
    ScratchRepo.insert_all("visits", [
      Map.merge(
        %{
          id: id,
          user_id: 8930,
          name: "Cafe",
          status: 0,
          started_at: @old,
          ended_at: ~N[2026-10-03 09:00:00],
          duration: 60,
          created_at: @old,
          updated_at: @old
        },
        attrs
      )
    ])
  end

  defp run(user, context, ids \\ ["893002", "893001"]),
    do: WebMerge.run(ScratchRepo, user, ids, context)

  defp point!,
    do:
      rows(
        "INSERT INTO points(user_id,visit_id,timestamp,lonlat,created_at,updated_at) VALUES(8930,893002,1791000000,ST_SetSRID(ST_MakePoint(12,51),4326),$1,$1)",
        [@old]
      )

  defp commands, do: rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

  test "merge spans local-day visits and reassigns points before deleting sources", %{
    user: user,
    context: context
  } do
    point!()

    ScratchRepo.insert_all("place_visits", [
      %{visit_id: 893_002, place_id: 893_011, created_at: @old, updated_at: @old}
    ])

    assert {:ok, %{visit: %{"id" => 893_001}, source_ids: [893_002]}} = run(user, context)

    assert [[" Cafe , Park", 1, 111, @old, ~N[2026-10-03 09:50:30.000000], @stamp, 893_010]] =
             rows(
               "SELECT name,status,duration,started_at,ended_at,updated_at,place_id FROM visits"
             )

    assert [[893_001]] = rows("SELECT visit_id FROM points")
    assert [[0]] = rows("SELECT count(*) FROM place_visits")

    assert [
             ["visit_months_changed", %{"user_id" => 8930, "started_at" => stamps}],
             ["places_delete_if_orphan", %{"user_id" => 8930, "place_ids" => [893_011]}]
           ] = commands()

    assert length(stamps) == 2
    assert {:error, :select_visits_to_merge} = run(user, context, ["893001"])

    for id <- 893_100..893_600, do: visit!(id, %{})

    assert {:ok, %{visit: %{"id" => 893_100}, source_ids: sources}} =
             run(user, context, Enum.map(893_100..893_600, &Integer.to_string/1))

    assert length(sources) == 500
  end

  test "same selected place preserves base name while mixed names deduplicate", %{
    user: user,
    context: context
  } do
    rows("UPDATE visits SET place_id=893010 WHERE id=893002")
    assert {:ok, %{visit: %{"id" => 893_001, "name" => " Cafe "}}} = run(user, context)
    visit!(893_002, %{name: "cafe", started_at: @old, ended_at: ~N[2026-10-03 09:30:00]})

    visit!(893_003, %{
      name: "Park",
      started_at: ~N[2026-10-03 09:30:00],
      ended_at: ~N[2026-10-03 09:40:00]
    })

    visit!(893_004, %{
      name: " \t",
      started_at: ~N[2026-10-03 09:40:00],
      ended_at: ~N[2026-10-03 09:45:00]
    })

    assert {:ok, %{visit: %{"name" => " Cafe , Park"}}} =
             run(user, context, ~w(893001 893002 893003 893004))

    rows("DELETE FROM visits")

    visit!(893_005, %{
      name: "First",
      started_at: ~N[2026-09-30 23:30:00],
      ended_at: ~N[2026-10-01 00:00:00]
    })

    visit!(893_006, %{
      name: "Second",
      started_at: ~N[2026-10-01 00:00:00],
      ended_at: ~N[2026-10-01 00:30:00]
    })

    assert {:ok, %{visit: %{"id" => 893_005, "name" => "First, Second"}}} =
             run(user, context, ~w(893006 893005))
  end

  test "cross-local-day selection has no write or effects", %{user: user, context: context} do
    rows("UPDATE visits SET started_at=$1,ended_at=$2 WHERE id=893001", [
      ~N[2026-10-02 21:30:00],
      ~N[2026-10-02 22:00:00]
    ])

    rows("UPDATE visits SET started_at=$1,ended_at=$2 WHERE id=893002", [
      ~N[2026-10-02 22:30:00],
      ~N[2026-10-02 23:00:00]
    ])

    assert {:error, :visits_must_share_day} = run(user, context)
    assert [[2]] = rows("SELECT count(*) FROM visits")
    assert commands() == []
  end

  test "merge with polymorphic notes hands back before any change", %{
    user: user,
    context: context
  } do
    point!()

    ScratchRepo.insert_all("notes", [
      %{
        user_id: 8930,
        attachable_id: 893_002,
        attachable_type: "Visit",
        title: "Synthetic note",
        created_at: @old,
        updated_at: @old
      }
    ])

    assert {:replay, _} = run(user, context)
    assert [[893_002]] = rows("SELECT visit_id FROM points")
    assert [[2]] = rows("SELECT count(*) FROM visits")
    assert [[1]] = rows("SELECT count(*) FROM notes")
    assert commands() == []
  end

  test "merge failure rolls back points visits and reverse commands together", %{
    user: user,
    context: context
  } do
    point!()

    rows(
      "ALTER TABLE phoenix.rails_commands ADD CONSTRAINT a8_merge_fail CHECK(kind<>'places_delete_if_orphan') NOT VALID"
    )

    try do
      assert {:replay, _} = run(user, context)
      assert [[893_002]] = rows("SELECT visit_id FROM points")
      assert [[0], [0]] = rows("SELECT status FROM visits ORDER BY id")
      assert commands() == []
    after
      rows("ALTER TABLE phoenix.rails_commands DROP CONSTRAINT a8_merge_fail")
    end
  end
end
