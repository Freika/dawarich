defmodule Dawarich.UserData.RestoreRawArchivesTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Restore.RawArchives

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    c = UserDataSeeds.seed!("v2", ScratchRepo)
    entries = UserDataSeeds.entries("export_UTC")

    data =
      entries["raw_data_archives.jsonl"]
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    %{c: c, entries: entries, data: data}
  end

  @tag :tmp_dir
  test "restore raw archives preserve portable metadata and duplicate identity", %{
    c: c,
    data: data,
    entries: entries,
    tmp_dir: dir
  } do
    item =
      hd(data)
      |> Map.put("id", 999_999)
      |> Map.put("user_id", 123)
      |> Map.put("dropped_column", true)
      |> Map.delete("content_type")

    bytes = entries["files/" <> item["file_name"]]
    File.write!(Path.join(dir, item["file_name"]), bytes)
    assert RawArchives.call(ScratchRepo, c.user_id, [item], dir, c.context) == [1, 1]
    assert RawArchives.call(ScratchRepo, c.user_id, [item], dir, c.context) == [0, 0]

    assert [[c.user_id, 2026, 1, 1, 3, "synthetic-checksum", item["metadata"]]] ==
             rows(
               "SELECT user_id,year,month,chunk_number,point_count,point_ids_checksum,metadata FROM points_raw_data_archives"
             )

    [[key, filename, type]] = rows("SELECT key,filename,content_type FROM active_storage_blobs")
    assert filename == item["original_filename"]
    assert type == "application/gzip"
    actual = File.read!(Dawarich.Storage.disk_path(c.context.storage.root, key))
    assert actual == bytes
    assert <<31, 139, _::binary>> = actual

    assert Base.encode16(:crypto.hash(:sha256, actual), case: :lower) ==
             item["metadata"]["content_checksum"]

    assert [["Points::RawDataArchive", "file"]] ==
             rows("SELECT record_type,name FROM active_storage_attachments")

    refute Map.has_key?(item["metadata"], "encryption")

    assert [[0]] ==
             rows("SELECT count(*) FROM points_raw_data_archives WHERE id=999999 OR user_id=123")

    variant =
      item
      |> Map.put("chunk_number", 2)
      |> Map.put("file_name", "../../" <> item["file_name"])
      |> Map.put("original_filename", "../../safe.gz")

    assert RawArchives.call(ScratchRepo, c.user_id, [variant], dir, c.context) == [1, 1]

    assert [["safe.gz"]] ==
             rows("SELECT filename FROM active_storage_blobs WHERE filename='safe.gz'")

    assert [] == rows("SELECT command_type FROM job_outbox")
  end

  @tag :tmp_dir
  test "restore raw attachment failure keeps created record and zero file count", %{
    c: c,
    data: data,
    entries: entries,
    tmp_dir: dir
  } do
    item = hd(data)
    error = Map.put(item, "file_error", "source export failed")
    assert RawArchives.call(ScratchRepo, c.user_id, [error], dir, c.context) == [0, 0]
    assert [[0]] == rows("SELECT count(*) FROM points_raw_data_archives")
    assert RawArchives.call(ScratchRepo, c.user_id, [item], dir, c.context) == [1, 0]
    assert [[1]] == rows("SELECT count(*) FROM points_raw_data_archives")

    bad =
      Enum.map(
        [
          {"year", 1970},
          {"year", 2100},
          {"month", 0},
          {"month", 13},
          {"point_count", 0},
          {"chunk_number", 0},
          {"point_ids_checksum", nil}
        ],
        fn {key, value} ->
          Map.put(item, key, value)
          |> Map.put("chunk_number", if(key == "chunk_number", do: value, else: 2))
        end
      )

    bad = bad ++ [nil, %{}, %{item | "chunk_number" => 2, "metadata" => %{"format_version" => 2}}]
    assert RawArchives.call(ScratchRepo, c.user_id, bad, dir, c.context) == [0, 0]

    for {name, index} <- Enum.with_index([nil, "", " ", ".", ".."], 2) do
      assert RawArchives.call(
               ScratchRepo,
               c.user_id,
               [%{item | "chunk_number" => index, "file_name" => name}],
               dir,
               c.context
             ) == [1, 0]
    end

    File.write!(Path.join(dir, item["file_name"]), entries["files/" <> item["file_name"]])
    broken = Map.put(c.context, :storage, %{service: "unsupported"})

    assert RawArchives.call(ScratchRepo, c.user_id, [%{item | "chunk_number" => 10}], dir, broken) ==
             [1, 0]

    assert [[0]] == rows("SELECT count(*) FROM active_storage_attachments")
    assert RawArchives.call(ScratchRepo, c.user_id, nil, dir, c.context) == [0, 0]
    stopped = Map.put(c.context, :fence, fn _ -> raise Dawarich.Imports.LeaseLost end)

    assert_raise Dawarich.Imports.LeaseLost, fn ->
      RawArchives.call(ScratchRepo, c.user_id, [%{item | "chunk_number" => 11}], dir, stopped)
    end
  end
end
