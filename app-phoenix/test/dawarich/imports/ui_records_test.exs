defmodule Dawarich.Imports.UiRecordsTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.UiRecords

  setup do
    Dawarich.ImportLeaseFixture.create()
  end

  test "owner-scoped read and update validate source and name", c do
    assert {:ok, record} = UiRecords.get(ScratchRepo, c.import.user_id, c.import.id)
    assert record.name == "lease.gpx"
    assert {:error, :not_found} = UiRecords.get(ScratchRepo, c.other, c.import.id)

    assert {:error, :invalid_source} =
             UiRecords.update(ScratchRepo, c.import.user_id, c.import.id, %{"source" => "unknown"})

    assert {:error, :not_found} =
             UiRecords.update(ScratchRepo, c.other, c.import.id, %{"name" => "stolen"})

    assert {:ok, _} =
             UiRecords.update(ScratchRepo, c.import.user_id, c.import.id, %{
               "name" => "renamed.gpx",
               "source" => "geojson"
             })

    assert [["renamed.gpx", 6, 5]] =
             rows(
               "SELECT name,source,additional_data_extraction_status FROM imports WHERE id=$1",
               [c.import.id]
             )
  end

  test "completed eligible extraction uses guarded native CAS and durable Rails handoff", c do
    rows("UPDATE imports SET status=2,raw_data=$2 WHERE id=$1", [
      c.import.id,
      %{"waypoints_seen" => 1}
    ])

    context = %{zone: "Europe/Berlin", locale: "fr", now: DateTime.utc_now()}

    assert {:ok, :queued} =
             UiRecords.extract(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               %{"trust_source" => false},
               context
             )

    assert {:error, :in_flight} =
             UiRecords.extract(ScratchRepo, c.import.user_id, c.import.id, %{}, context)

    assert [[1]] =
             rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
               c.import.id
             ])

    assert [[%{"trust_source" => false}]] =
             rows("SELECT additional_data_extraction->'options' FROM imports WHERE id=$1", [
               c.import.id
             ])

    assert [["imports.extraction_requested", %{"locale" => "fr"}]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")
             |> Enum.map(fn [k, p] -> [k, Map.take(p, ["locale"])] end)
  end

  test "manual extraction replaces stale options with the Rails trust_source contract", c do
    data = %{"options" => "legacy"}

    rows("UPDATE imports SET status=2,raw_data=$2,additional_data_extraction=$3 WHERE id=$1", [
      c.import.id,
      %{"waypoints_seen" => 1},
      data
    ])

    assert {:ok, :queued} =
             UiRecords.extract(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               %{"trust_source" => false},
               %{
                 zone: "UTC",
                 locale: "en",
                 now: DateTime.utc_now()
               }
             )

    assert [[%{"options" => %{"trust_source" => false}}, 1]] =
             rows(
               "SELECT additional_data_extraction,additional_data_extraction_status FROM imports WHERE id=$1",
               [c.import.id]
             )

    assert [[1]] == rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "manual extraction admits supported processing imports with run identity", c do
    rows("UPDATE imports SET status=1,raw_data=$2 WHERE id=$1", [
      c.import.id,
      %{"waypoints_seen" => 1}
    ])

    assert {:ok, :queued} =
             UiRecords.extract(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               %{"trust_source" => false},
               %{zone: "Berlin", locale: "fr", now: DateTime.utc_now()}
             )

    assert [
             [
               "imports.extraction_requested",
               %{
                 "import_id" => id,
                 "user_id" => user,
                 "source" => 4,
                 "event_id" => event,
                 "started_at" => started
               }
             ]
           ] = rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert id == c.import.id and user == c.import.user_id
    assert is_binary(event) and is_binary(started)
  end

  test "removal requires owner and quiescent supported extraction and persists guarded handoff",
       c do
    rows(
      "UPDATE imports SET status=2,additional_data_extraction_status=3,additional_data_extraction=$2 WHERE id=$1",
      [c.import.id, %{"counts" => %{"places" => 2}}]
    )

    context = %{zone: "Berlin", locale: "fr", now: DateTime.utc_now()}

    assert {:error, :not_found} =
             UiRecords.remove_extraction(ScratchRepo, c.other, c.import.id, context)

    assert {:ok, :queued} =
             UiRecords.remove_extraction(ScratchRepo, c.import.user_id, c.import.id, context)

    assert {:error, :in_flight} =
             UiRecords.remove_extraction(ScratchRepo, c.import.user_id, c.import.id, context)

    assert [
             [
               2,
               %{
                 "counts" => %{"places" => 2},
                 "phoenix_extraction_action" => "remove",
                 "phoenix_extraction_event" => event,
                 "started_at" => started
               }
             ]
           ] =
             rows(
               "SELECT additional_data_extraction_status,additional_data_extraction FROM imports WHERE id=$1",
               [c.import.id]
             )

    assert [
             [
               "imports.extraction_destroy_requested",
               %{"event_id" => ^event, "started_at" => ^started, "source" => 4}
             ]
           ] = rows("SELECT kind,payload FROM phoenix.rails_commands")
  end

  test "soft-deleted actors cannot read or edit retained imports", c do
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.import.user_id])
    assert {:error, :not_found} = UiRecords.get(ScratchRepo, c.import.user_id, c.import.id)

    assert {:error, :not_found} =
             UiRecords.update(ScratchRepo, c.import.user_id, c.import.id, %{
               "name" => "stale-owner"
             })

    assert [["lease.gpx"]] = rows("SELECT name FROM imports WHERE id=$1", [c.import.id])
  end
end
