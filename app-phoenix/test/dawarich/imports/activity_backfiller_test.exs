defmodule Dawarich.Imports.ActivityBackfillerTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.ActivityBackfiller
  alias Dawarich.Imports.ActivityBackfill.File, as: BackfillFile

  @stamp ~N[2026-01-15 23:30:00]
  @fixture Path.expand("../../fixtures/a12rel/imports.json", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "a12rel-backfill-#{System.unique_integer([:positive])}")
    tmp = Path.join(root, "tmp")
    File.mkdir_p!(tmp)

    on_exit(fn ->
      rows("DELETE FROM active_storage_attachments WHERE id IN (54001,54002)")
      rows("DELETE FROM active_storage_blobs WHERE id IN (54001,54002)")
      rows("DELETE FROM imports WHERE id=54001")
      rows("DELETE FROM users WHERE id=54001")
      File.rm_rf!(root)
    end)

    %{root: root, tmp: tmp, services: %{"local" => %{service: "local", root: root}}}
  end

  test "activity backfill preserves support attachment and rescued download behavior", c do
    seed!(c)
    context = %{services: c.services, temp_dir: c.tmp}
    fixture = @fixture |> File.read!() |> Jason.decode!()
    assert false == ActivityBackfiller.call(ScratchRepo, 54_999, context)

    for source <- [nil, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15] do
      rows("UPDATE imports SET source=$1 WHERE id=54001", [source])
      refute ActivityBackfiller.call(ScratchRepo, 54_001, context)
    end

    rows("UPDATE imports SET source=0 WHERE id=54001")
    rows("UPDATE active_storage_attachments SET name='prepared_download' WHERE id=54001")
    refute ActivityBackfiller.call(ScratchRepo, 54_001, context)
    rows("UPDATE active_storage_attachments SET name='file' WHERE id=54001")

    ScratchRepo.insert_all("active_storage_blobs", [
      %{
        id: 54_002,
        key: "missing_second_blob",
        filename: "other.json",
        byte_size: 2,
        checksum: "bad",
        service_name: "unconfigured",
        created_at: @stamp
      }
    ])

    ScratchRepo.insert_all("active_storage_attachments", [
      %{
        id: 54_002,
        record_type: "Import",
        record_id: 54_001,
        name: "file",
        blob_id: 54_002,
        created_at: @stamp
      }
    ])

    assert BackfillFile.attachment(ScratchRepo, 54_001).id == 54_001

    for {source, id} <- [{2, "google_records"}, {1, "owntracks"}, {6, "geojson"}] do
      source_case = Enum.find(fixture["cases"], &(&1["id"] == id))
      assert source_case["error"] == nil
      assert source_case["downloads"] == 0
      rows("UPDATE imports SET source=$1 WHERE id=54001", [source])
      assert ActivityBackfiller.call(ScratchRepo, 54_001, %{context | services: :not_a_catalog})
      assert File.ls!(c.tmp) == []
    end

    for source <- [0, 3] do
      rows("UPDATE imports SET source=$1 WHERE id=54001", [source])
      assert ActivityBackfiller.call(ScratchRepo, 54_001, context)
      assert File.ls!(c.tmp) == []
    end

    blob = BackfillFile.attachment(ScratchRepo, 54_001)
    parent = self()

    assert :ok ==
             BackfillFile.with_file(blob, context, fn path ->
               assert File.read!(path) == "{}"
               assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
               send(parent, {:download_path, path})
             end)

    assert_receive {:download_path, path}
    refute File.exists?(path)
    assert File.ls!(c.tmp) == []

    assert_raise Postgrex.Error, fn ->
      BackfillFile.with_file(blob, context, fn _ ->
        rows("SELECT a12rel_missing_column FROM imports")
      end)
    end

    assert_raise RuntimeError, "unexpected parser failure", fn ->
      BackfillFile.with_file(blob, context, fn _ -> raise "unexpected parser failure" end)
    end

    assert_raise FunctionClauseError, fn ->
      BackfillFile.with_file(blob, %{context | temp_dir: nil}, fn _ ->
        flunk("invalid context")
      end)
    end

    assert File.ls!(c.tmp) == []

    for {id, update} <- [
          {"checksum", "checksum='AAAAAAAAAAAAAAAAAAAAAA=='"},
          {"size", "byte_size=999"},
          {"empty", "byte_size=0"},
          {"download_error", "key='missing_disk_blob'"},
          {nil, "service_name='unconfigured'"},
          {nil, "key='../unsafe'"}
        ] do
      restore_blob!(c)
      if id == "empty", do: File.write!(Dawarich.Storage.disk_path(c.root, blob.key), "")
      rows("UPDATE active_storage_blobs SET #{update} WHERE id=54001")

      if id do
        source_case = Enum.find(fixture["cases"], &(&1["id"] == id))
        assert source_case["error"] == nil
        assert source_case["downloads"] == 1

        if id in ["checksum", "size"] do
          refute source_case["before"]["points"] == source_case["after"]["points"]
        end
      end

      current = BackfillFile.attachment(ScratchRepo, 54_001)

      assert :ok ==
               BackfillFile.with_file(current, context, fn _ ->
                 flunk("rejected blob reached activity processing")
               end)

      assert ActivityBackfiller.call(ScratchRepo, 54_001, context)
      assert File.ls!(c.tmp) == []
    end

    restore_blob!(c)
    rows("UPDATE imports SET status=4 WHERE id=54001")
    assert ActivityBackfiller.call(ScratchRepo, 54_001, context)
    rows("DELETE FROM imports WHERE id=54001")
    refute ActivityBackfiller.call(ScratchRepo, 54_001, context)
  end

  defp seed!(c) do
    ScratchRepo.insert_all("users", [
      %{id: 54_001, email: "a12rel-shell@example.invalid", created_at: @stamp, updated_at: @stamp}
    ])

    ScratchRepo.insert_all("imports", [
      %{
        id: 54_001,
        user_id: 54_001,
        name: "a12rel-shell",
        source: 0,
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    ScratchRepo.insert_all("active_storage_blobs", [
      %{
        id: 54_001,
        key: "abcd_a12rel_shell",
        filename: "shell.json",
        byte_size: 2,
        checksum: Base.encode64(:crypto.hash(:md5, "{}")),
        service_name: "local",
        created_at: @stamp
      }
    ])

    ScratchRepo.insert_all("active_storage_attachments", [
      %{
        id: 54_001,
        record_type: "Import",
        record_id: 54_001,
        name: "file",
        blob_id: 54_001,
        created_at: @stamp
      }
    ])

    restore_blob!(c)
  end

  defp restore_blob!(c) do
    path = Dawarich.Storage.disk_path(c.root, "abcd_a12rel_shell")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "{}")

    rows(
      "UPDATE active_storage_blobs SET key='abcd_a12rel_shell',service_name='local',byte_size=2,checksum=$1 WHERE id=54001",
      [Base.encode64(:crypto.hash(:md5, "{}"))]
    )
  end
end
