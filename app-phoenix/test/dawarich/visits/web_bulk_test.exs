defmodule Dawarich.Visits.WebBulkTest do
  use Dawarich.JobsCase
  alias Dawarich.Visits.WebBulk
  @now ~U[2026-10-03 10:00:00Z]
  @old ~N[2026-09-30 09:00:00.000000]
  @stamp ~N[2026-10-03 10:00:00.000000]

  setup do
    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(places  tags  taggings  visits  place_visits  areas  notes)
    )

    for id <- [8920, 8921] do
      ScratchRepo.insert_all("users", [
        %{
          id: id,
          email: "a8-bulk-#{id}@dawarich.test",
          encrypted_password: "synthetic",
          settings: %{},
          created_at: @old,
          updated_at: @old
        }
      ])
    end

    %{
      user: %{id: 8920, settings: %{"timezone" => "Europe/Berlin"}},
      context: %{now: @now, self_hosted: true}
    }
  end

  defp visit!(id, attrs \\ %{}) do
    ScratchRepo.insert_all("visits", [
      Map.merge(
        %{
          id: id,
          user_id: 8920,
          name: "Cafe",
          status: 0,
          started_at: @old,
          ended_at: ~N[2026-09-30 10:00:00],
          duration: 60,
          created_at: @old,
          updated_at: @old
        },
        attrs
      )
    ])
  end

  defp run(action, user, params, context),
    do: WebBulk.run(ScratchRepo, action, user, params, context)

  defp payload(kind),
    do:
      rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1 ORDER BY id", [kind])
      |> Enum.map(&hd/1)

  defp place! do
    ScratchRepo.insert_all("places", [
      %{
        id: 892_010,
        user_id: 8920,
        name: "Demo place",
        demo: true,
        latitude: Decimal.new("51"),
        longitude: Decimal.new("12"),
        created_at: @old,
        updated_at: @old
      }
    ])
  end

  test "501 selected web visits is refused without partial changes", %{
    user: user,
    context: context
  } do
    for id <- 1..501, do: visit!(892_000 + id)
    ids = Enum.map(1..501, &Integer.to_string(892_000 + &1))

    assert {:error, :too_many} =
             run(:update, user, %{"visit_ids" => ids, "status" => "confirmed"}, context)

    assert [[501]] = rows("SELECT count(*) FROM visits WHERE status=0")
    assert payload("visit_months_changed") == []

    assert {:ok, %{count: 500}} =
             run(
               :update,
               user,
               %{"visit_ids" => Enum.take(ids, 500), "status" => "confirmed"},
               context
             )

    assert [[500]] = rows("SELECT count(*) FROM visits WHERE status=1")
  end

  test "suggested date selection and explicit ids have distinct scope rules", %{
    user: user,
    context: context
  } do
    visit!(892_001, %{started_at: ~N[2026-10-02 22:30:00], ended_at: ~N[2026-10-02 23:30:00]})

    visit!(892_002, %{
      status: 1,
      started_at: ~N[2026-10-02 23:00:00],
      ended_at: ~N[2026-10-03 00:00:00]
    })

    visit!(892_003)
    visit!(892_004, %{user_id: 8921})

    assert {:error, :missing} =
             run(
               :update,
               user,
               %{"visit_ids" => ["892003", "892004"], "status" => "confirmed"},
               context
             )

    assert {:ok, %{count: 1, ids: [892_001], date: "2026-10-03", source_status: "suggested"}} =
             run(:update, user, %{"date" => "2026-10-03", "status" => "confirmed"}, context)

    assert [[0]] = rows("SELECT status FROM visits WHERE id=892003")

    assert {:ok, %{count: 1}} =
             run(
               :update,
               user,
               %{"visit_ids" => ["892002"], "status" => "suggested", "date" => "2026-09-01"},
               context
             )

    assert [[0]] = rows("SELECT status FROM visits WHERE id=892002")
  end

  test "unknown source status and empty delete selection preserve Rails errors", %{
    user: user,
    context: context
  } do
    visit!(892_001)

    assert {:error, :unsupported_source_status} =
             run(
               :update,
               user,
               %{"source_status" => "confirmed", "status" => "confirmed"},
               context
             )

    assert {:error, :select_visit_to_delete} = run(:destroy, user, %{}, context)

    assert {:error, :no_matching_visits} =
             run(
               :destroy,
               user,
               %{"date" => "2026-10-03", "source_status" => "suggested"},
               context
             )

    assert {:error, :failed_to_update_visits} =
             run(:update, user, %{"date" => "2026-10-03", "status" => "confirmed"}, context)

    assert {:error, :failed_to_update_visits} =
             run(:update, user, %{"visit_ids" => ["892001"], "status" => "invalid"}, context)

    assert payload("visit_months_changed") == []
    assert [[0]] = rows("SELECT status FROM visits WHERE id=892001")
  end

  test "bulk confirmation skips adoption and updated_at callbacks", %{
    user: user,
    context: context
  } do
    place!()
    visit!(892_001, %{demo: true, place_id: 892_010})

    assert {:ok, %{count: 1}} =
             run(:update, user, %{"visit_ids" => ["892001"], "status" => "confirmed"}, context)

    assert [[1, true, @old]] = rows("SELECT status,demo,updated_at FROM visits WHERE id=892001")
    assert [[true, @old]] = rows("SELECT demo,updated_at FROM places WHERE id=892010")
    assert payload("places_delete_if_orphan") == []
  end

  test "bulk decline queues distinct orphan places and retains points", %{
    user: user,
    context: context
  } do
    place!()
    visit!(892_001, %{demo: true, place_id: 892_010})

    visit!(892_002, %{
      place_id: 892_010,
      started_at: ~N[2026-09-30 10:00:00],
      ended_at: ~N[2026-09-30 11:00:00]
    })

    rows(
      "INSERT INTO points(user_id,visit_id,timestamp,lonlat,created_at,updated_at) VALUES(8920,892001,1791000000,ST_SetSRID(ST_MakePoint(12,51),4326),$1,$1)",
      [@old]
    )

    assert {:ok, %{count: 2}} =
             run(
               :update,
               user,
               %{"visit_ids" => ["892001", "892002"], "status" => "declined"},
               context
             )

    assert [[2, @old], [2, @old]] = rows("SELECT status,updated_at FROM visits ORDER BY id")
    assert [[892_001]] = rows("SELECT visit_id FROM points")
    assert [%{"user_id" => 8920, "place_ids" => [892_010]}] = payload("places_delete_if_orphan")
  end

  test "bulk destroy tombstones all selected rows without removing links", %{
    user: user,
    context: context
  } do
    place!()
    visit!(892_001, %{place_id: 892_010})

    visit!(892_002, %{
      place_id: 892_010,
      started_at: ~N[2026-10-03 09:00:00],
      ended_at: ~N[2026-10-03 10:00:00]
    })

    for id <- [892_001, 892_002],
        do:
          ScratchRepo.insert_all("place_visits", [
            %{visit_id: id, place_id: 892_010, created_at: @old, updated_at: @old}
          ])

    assert {:ok, %{count: 2, dates: [~D[2026-09-30], ~D[2026-10-03]]}} =
             run(:destroy, user, %{"visit_ids" => ["892001", "892002"]}, context)

    assert [[@stamp, @old], [@stamp, @old]] =
             rows("SELECT deleted_at,updated_at FROM visits ORDER BY id")

    assert [[2]] = rows("SELECT count(*) FROM place_visits")
    assert [%{"user_id" => 8920, "place_ids" => [892_010]}] = payload("places_delete_if_orphan")

    assert [%{"started_at" => stamps}] =
             Enum.map(payload("visit_months_changed"), &Map.delete(&1, "user_id"))

    assert length(stamps) == 2
  end
end
