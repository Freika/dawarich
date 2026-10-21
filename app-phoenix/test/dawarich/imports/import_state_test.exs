defmodule Dawarich.Imports.ImportStateTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{ImportState, Lease, LeaseLost}

  setup do
    c = Dawarich.ImportLeaseFixture.create()

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,byte_size,checksum,service_name,created_at) VALUES ('stateblob','state.gpx',6,'checksum','local',now()) RETURNING id"
      )

    [[attachment]] =
      rows(
        "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'file',$2,now()) RETURNING id",
        [c.import.id, blob]
      )

    Map.merge(c, %{blob: blob, attachment: attachment})
  end

  defp run(c, fun),
    do:
      Lease.with_import(ScratchRepo, c.job, c.import, fn lease ->
        ImportState.with_snapshot(lease, fn state -> fun.(lease, state) end)
      end)

  test "processing resets raw counters only after explicit admission", c do
    rows("UPDATE imports SET raw_points=8,doubles=5,processed=7 WHERE id=$1", [c.import.id])

    assert {:ok, :ok} =
             run(c, fn lease, state ->
               assert state.blob.filename == "state.gpx"

               assert [[0, 8, 5, 7]] ==
                        rows(
                          "SELECT status,raw_points,doubles,processed FROM imports WHERE id=$1",
                          [c.import.id]
                        )

               ImportState.start!(lease, ~U[2026-01-01 00:00:00Z])

               assert [[1, 0, 0, 7]] ==
                        rows(
                          "SELECT status,raw_points,doubles,processed FROM imports WHERE id=$1",
                          [c.import.id]
                        )

               :ok
             end)
  end

  for {name, sql, field} <- [
        {"attachment removed", "DELETE FROM active_storage_attachments WHERE id=$1", :attachment},
        {"blob checksum changed",
         "UPDATE active_storage_blobs SET checksum='changed' WHERE id=$1", :blob},
        {"blob bytes changed", "UPDATE active_storage_blobs SET byte_size=7 WHERE id=$1", :blob},
        {"blob service changed",
         "UPDATE active_storage_blobs SET service_name='other' WHERE id=$1", :blob},
        {"external phase changed", "UPDATE imports SET status=3 WHERE id=$1", :import}
      ] do
    test "#{name} stops a pinned lifecycle", c do
      assert {:ok, :ok} =
               run(c, fn lease, _ ->
                 ImportState.start!(lease, DateTime.utc_now())

                 rows(unquote(sql), [
                   Map.fetch!(c, unquote(field))
                   |> then(fn value -> if is_map(value), do: value.id, else: value end)
                 ])

                 assert_raise LeaseLost, fn ->
                   ImportState.effect!(lease, fn -> flunk("stale effect") end)
                 end

                 :ok
               end)
    end
  end

  test "completed phase resumes only the same persisted event and attachment", c do
    assert {:ok, :ok} =
             run(c, fn lease, _ ->
               ImportState.start!(lease, DateTime.utc_now())
               ImportState.complete!(lease, DateTime.utc_now())

               assert_raise LeaseLost, fn ->
                 Lease.effect!(lease, fn -> :invalid_processing_effect end)
               end

               assert :terminal = ImportState.mode(lease)
               ImportState.effect!(lease, fn -> :ok end)
             end)

    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    newer = %{c | job: %{c.job | attempt: 2}}
    assert {:ok, :terminal} = run(newer, fn lease, _ -> ImportState.mode(lease) end)
    rows("UPDATE active_storage_blobs SET checksum='replaced' WHERE id=$1", [c.blob])
    assert_raise LeaseLost, fn -> run(newer, fn _, _ -> flunk("replaced terminal blob") end) end
  end

  test "failed phase retains counters and prevents completion", c do
    assert {:ok, :ok} =
             run(c, fn lease, _ ->
               ImportState.fail!(lease, RuntimeError.exception("bad blob"), DateTime.utc_now())

               assert [[3, "bad blob"]] ==
                        rows("SELECT status,error_message FROM imports WHERE id=$1", [c.import.id])

               assert :failed = ImportState.mode(lease)
               assert :ok = ImportState.complete!(lease, DateTime.utc_now())
             end)

    assert [[3]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
  end

  test "resuming an already processing import preserves its original start time", c do
    rows("UPDATE imports SET status=1,processing_started_at='2025-12-31T00:00:00' WHERE id=$1", [
      c.import.id
    ])

    assert {:ok, :ok} =
             run(c, fn lease, _ -> ImportState.start!(lease, ~U[2026-01-01 00:00:00Z]) end)

    assert [[~N[2025-12-31 00:00:00.000000]]] ==
             rows("SELECT processing_started_at FROM imports WHERE id=$1", [c.import.id])
  end

  test "status saves normalize supported GPX extraction availability", c do
    rows("UPDATE imports SET additional_data_extraction_status=5 WHERE id=$1", [c.import.id])

    assert {:ok, :ok} =
             run(c, fn lease, _ ->
               ImportState.fail!(
                 lease,
                 RuntimeError.exception("bad download"),
                 DateTime.utc_now()
               )
             end)

    assert [[0]] ==
             rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
               c.import.id
             ])
  end
end
