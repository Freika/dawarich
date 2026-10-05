defmodule Dawarich.Visits.WebDeleteTest do
  use Dawarich.JobsCase
  alias Dawarich.Visits.WebDelete
  @now ~U[2026-10-03 10:00:00Z]
  @old ~N[2026-09-30 09:00:00.000000]
  @stamp ~N[2026-10-03 10:00:00.000000]

  test "soft delete retains points place links notes and tombstone" do
    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(places  tags  taggings  visits  place_visits  areas  notes)
    )

    ScratchRepo.insert_all("users", [
      %{
        id: 8910,
        email: "a8-delete@dawarich.test",
        encrypted_password: "synthetic",
        settings: %{},
        created_at: @old,
        updated_at: @old
      }
    ])

    ScratchRepo.insert_all("places", [
      %{
        id: 891_010,
        user_id: 8910,
        name: "Place",
        latitude: Decimal.new("51"),
        longitude: Decimal.new("12"),
        created_at: @old,
        updated_at: @old
      }
    ])

    ScratchRepo.insert_all("visits", [
      %{
        id: 891_000,
        user_id: 8910,
        place_id: 891_010,
        name: "Cafe",
        status: 1,
        started_at: @old,
        ended_at: ~N[2026-09-30 10:00:00],
        duration: 60,
        created_at: @old,
        updated_at: @old
      }
    ])

    ScratchRepo.insert_all("place_visits", [
      %{visit_id: 891_000, place_id: 891_010, created_at: @old, updated_at: @old}
    ])

    ScratchRepo.insert_all("notes", [
      %{
        user_id: 8910,
        attachable_id: 891_000,
        attachable_type: "Visit",
        title: "Synthetic note",
        created_at: @old,
        updated_at: @old
      }
    ])

    rows(
      "INSERT INTO points(user_id,visit_id,timestamp,lonlat,created_at,updated_at) VALUES(8910,891000,1791000000,ST_SetSRID(ST_MakePoint(12,51),4326),$1,$1)",
      [@old]
    )

    user = %{id: 8910, settings: %{"timezone" => "Europe/Berlin"}}
    context = %{now: @now, self_hosted: true}
    assert {:ok, _} = WebDelete.run(ScratchRepo, user, 891_000, %{}, context)

    assert [[@stamp, @stamp, 1]] =
             rows("SELECT deleted_at,updated_at,status FROM visits WHERE id=891000")

    for table <- ~w(points place_visits),
        do: assert(rows("SELECT count(*) FROM #{table} WHERE visit_id=891000") == [[1]])

    assert [[1]] =
             rows(
               "SELECT count(*) FROM notes WHERE attachable_type='Visit' AND attachable_id=891000"
             )

    assert [[%{"user_id" => 8910, "place_ids" => [891_010]}]] =
             rows(
               "SELECT payload FROM phoenix.rails_commands WHERE kind='places_delete_if_orphan'"
             )

    assert {:error, :missing} = WebDelete.run(ScratchRepo, user, 891_000, %{}, context)
  end
end
