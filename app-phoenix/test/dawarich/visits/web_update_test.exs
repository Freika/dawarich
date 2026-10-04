defmodule Dawarich.Visits.WebUpdateTest do
  use Dawarich.JobsCase
  alias Dawarich.Visits.WebUpdate
  @now ~U[2026-10-03 10:00:00Z]
  @old ~N[2026-09-30 09:00:00.000000]
  @stamp ~N[2026-10-03 10:00:00.000000]

  setup do
    rows(
      "TRUNCATE places, tags, taggings, visits, place_visits, areas, notes RESTART IDENTITY CASCADE"
    )

    for id <- [8910, 8911] do
      ScratchRepo.insert_all("users", [
        %{
          id: id,
          email: "a8-edit-#{id}@dawarich.test",
          encrypted_password: "synthetic",
          settings: %{"timezone" => "Europe/Berlin"},
          created_at: @old,
          updated_at: @old
        }
      ])
    end

    ScratchRepo.insert_all("visits", [
      %{
        id: 891_000,
        user_id: 8910,
        name: "Cafe",
        status: 0,
        started_at: @old,
        ended_at: ~N[2026-09-30 10:00:00],
        duration: 60,
        created_at: @old,
        updated_at: @old
      }
    ])

    %{
      user: %{id: 8910, settings: %{"timezone" => "Europe/Berlin"}},
      context: %{now: @now, self_hosted: true}
    }
  end

  defp run(user, attrs, context), do: WebUpdate.run(ScratchRepo, user, 891_000, attrs, context)

  defp visit,
    do: rows("SELECT name,status,updated_at,demo,place_id,duration FROM visits WHERE id=891000")

  defp place!(id, owner, demo \\ false),
    do:
      ScratchRepo.insert_all("places", [
        %{
          id: id,
          user_id: owner,
          name: "Place #{id}",
          latitude: Decimal.new("51"),
          longitude: Decimal.new("12"),
          demo: demo,
          created_at: @old,
          updated_at: @old
        }
      ])

  defp payload(kind),
    do:
      rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1 ORDER BY id", [kind])
      |> Enum.map(&hd/1)

  test "renaming a suggested visit trims name and confirms it", %{user: user, context: context} do
    assert {:ok, result} = run(user, %{"name" => " \tNew cafe\n"}, context)
    assert result.visit["name"] == "New cafe"
    assert [["New cafe", 1, @stamp, false, nil, 60]] = visit()
    assert {:replay, _} = run(user, %{"name" => nil}, context)
    assert {:replay, _} = run(user, %{"status" => %{}}, context)
  end

  test "blank name keeps the old name and explicit decline wins", %{user: user, context: context} do
    assert {:ok, _} = run(user, %{"name" => " \n\t", "status" => "declined"}, context)
    assert [["Cafe", 2, @stamp, false, nil, 60]] = visit()
  end

  test "selected suggested place is permitted and foreign area is refused", %{
    user: user,
    context: context
  } do
    place!(891_010, 8911)
    place!(891_011, 8911)

    ScratchRepo.insert_all("place_visits", [
      %{visit_id: 891_000, place_id: 891_010, created_at: @old, updated_at: @old}
    ])

    ScratchRepo.insert_all("areas", [
      %{
        id: 891_020,
        user_id: 8911,
        name: "Foreign area",
        radius: 50,
        latitude: Decimal.new("51"),
        longitude: Decimal.new("12"),
        created_at: @old,
        updated_at: @old
      }
    ])

    assert {:error, :invalid_area} =
             run(user, %{"place_id" => "891010", "area_id" => "891020"}, context)

    assert [["Cafe", 0, @old, false, nil, 60]] = visit()
    assert payload("visit_months_changed") == []
    assert {:error, :invalid_place} = run(user, %{"place_id" => "891011"}, context)
    assert {:ok, _} = run(user, %{"place_id" => "891010"}, context)
    assert [["Place 891010", 1, @stamp, false, 891_010, 60]] = visit()
  end

  test "demo visit adoption propagates to the selected demo place and tags", %{
    user: user,
    context: context
  } do
    place!(891_010, 8910, true)
    rows("UPDATE visits SET demo=true,place_id=891010 WHERE id=891000")

    ScratchRepo.insert_all("tags", [
      %{
        id: 891_020,
        user_id: 8910,
        name: "Demo cafe",
        demo: true,
        created_at: @old,
        updated_at: @old
      }
    ])

    ScratchRepo.insert_all("taggings", [
      %{
        tag_id: 891_020,
        taggable_type: "Place",
        taggable_id: 891_010,
        created_at: @old,
        updated_at: @old
      }
    ])

    assert {:ok, _} = run(user, %{"place_id" => "891010"}, context)
    assert [["Place 891010", 1, @stamp, false, 891_010, 60]] = visit()
    assert [[false, @stamp]] = rows("SELECT demo,updated_at FROM places WHERE id=891010")
    assert [[false, @stamp]] = rows("SELECT demo,updated_at FROM tags WHERE id=891020")
    rows("UPDATE visits SET demo=false WHERE id=891000")
    rows("UPDATE places SET demo=true WHERE id=891010")
    rows("UPDATE tags SET demo=true WHERE id=891020")
    rows("UPDATE visits SET place_id=NULL WHERE id=891000")
    assert {:ok, _} = run(user, %{"place_id" => "891010", "status" => "declined"}, context)
    assert [[false]] = rows("SELECT demo FROM places WHERE id=891010")
    assert [[false]] = rows("SELECT demo FROM tags WHERE id=891020")
  end

  test "time edit preserves duration and emits both old and new month stamps", %{
    user: user,
    context: context
  } do
    assert {:ok, result} =
             run(
               user,
               %{"started_at" => "2026-10-01T08:00:00Z", "ended_at" => "2026-10-01T10:00:00Z"},
               context
             )

    assert result.visit["duration"] == 60
    assert [%{"user_id" => 8910, "started_at" => stamps}] = payload("visit_months_changed")
    assert Enum.sort(stamps) == ["2026-09-30T09:00:00.000000Z", "2026-10-01T08:00:00Z"]
    assert {:replay, _} = run(user, %{"ended_at" => "2026-09-01T00:00:00Z"}, context)
    assert length(payload("visit_months_changed")) == 1
  end

  test "decline and place reassignment enqueue the exact orphan identities", %{
    user: user,
    context: context
  } do
    place!(891_010, 8910)
    place!(891_011, 8910)
    rows("UPDATE visits SET place_id=891010 WHERE id=891000")
    assert {:ok, _} = run(user, %{"place_id" => "891011", "status" => "declined"}, context)

    assert [%{"user_id" => 8910, "place_ids" => [891_010, 891_011]}] =
             payload("places_delete_if_orphan")
  end
end
