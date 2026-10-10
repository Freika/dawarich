defmodule Dawarich.UserData.RestoreFilesTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Restore.{Imports, Exports, Trips}

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    c = UserDataSeeds.seed!("v2", ScratchRepo)
    entries = UserDataSeeds.entries("export_UTC")
    dir = Path.join(c.context.storage.root, "archive-files")
    File.mkdir_p!(dir)

    for {name, bytes} <- entries,
        String.starts_with?(name, "files/"),
        do: File.write!(Path.join(dir, Path.basename(name)), bytes)

    data =
      Map.new(~w(imports exports trips), fn name ->
        {name,
         entries[name <> ".jsonl"] |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)}
      end)

    %{c: c, data: data, dir: dir}
  end

  @tag :tmp_dir
  test "restore imports exports and trips preserve identity and suppress jobs", %{
    c: c,
    data: data,
    dir: dir,
    tmp_dir: output
  } do
    assert Imports.call(ScratchRepo, c.user_id, data["imports"], dir, c.context) == [1, 1]
    assert Exports.call(ScratchRepo, c.user_id, data["exports"], dir, c.context) == [2, 1]
    assert Trips.call(ScratchRepo, c.user_id, data["trips"], c.context) == 1

    for {module, name} <- [
          {Dawarich.UserData.Export.Imports, "imports"},
          {Dawarich.UserData.Export.Exports, "exports"},
          {Dawarich.UserData.Export.Trips, "trips"}
        ] do
      [entry] = module.write(ScratchRepo, c.user_id, output, c.context)

      actual =
        entry.path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)
        |> Enum.map(
          &Map.drop(&1, ~w(file_name original_filename file_size content_type file_error))
        )
        |> Enum.map(&utc_timestamps/1)

      expected =
        Enum.map(c.expected["rows"][name], &Map.drop(&1, ~w(file raw_data trip_source_id)))

      assert actual == expected
    end

    for {type, name} <- [{"Import", "imports"}, {"Export", "exports"}] do
      [[filename, content_type, key]] =
        rows(
          "SELECT b.filename,b.content_type,b.key FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type=$1",
          [type]
        )

      expected = hd(c.expected["rows"][name])["file"]
      assert filename == expected["filename"]
      assert content_type == expected["content_type"]
      assert Dawarich.Storage.get!(c.context.storage, key) == Base.decode64!(expected["bytes"])

      assert [["object", "true"]] ==
               rows(
                 "SELECT jsonb_typeof(metadata::jsonb),metadata::jsonb->>'identified' FROM active_storage_blobs WHERE key=$1",
                 [key]
               )
    end

    assert Imports.call(ScratchRepo, c.user_id, data["imports"], dir, c.context) == [0, 0]
    assert Exports.call(ScratchRepo, c.user_id, data["exports"], dir, c.context) == [0, 0]
    assert Trips.call(ScratchRepo, c.user_id, data["trips"], c.context) == 0
    changed = hd(data["imports"]) |> Map.put("created_at", "2025-01-01T00:00:00Z")
    assert Imports.call(ScratchRepo, c.user_id, [changed], dir, c.context) == [0, 0]

    trip =
      hd(data["trips"])
      |> Map.put("name", "duplicate in same input")
      |> Map.put("id", 999_999)
      |> Map.put("user_id", 123)

    assert Trips.call(ScratchRepo, c.user_id, [trip, trip], c.context) == 2

    assert [[2, c.user_id]] ==
             rows(
               "SELECT count(*),min(user_id) FROM trips WHERE name='duplicate in same input' AND id<>999999"
             )

    snapshot = %{
      "days" => [
        %{"date" => "2026-02-01", "day_number" => 1, "places" => [%{"name" => "planned stop"}]}
      ]
    }

    planned =
      trip
      |> Map.put("name", "planned")
      |> Map.put("source_identifier", "archive-source")
      |> Map.put("source_snapshot", snapshot)

    assert Trips.call(ScratchRepo, c.user_id, [planned], c.context) == 1

    assert [[1, "planned stop"]] ==
             rows(
               "SELECT t.source_status,s.name FROM trips t JOIN planned_days d ON d.trip_id=t.id JOIN planned_stops s ON s.planned_day_id=d.id WHERE t.name='planned'"
             )

    assert Trips.call(
             ScratchRepo,
             c.user_id,
             [%{planned | "name" => "invalid planned", "ended_at" => "2025-01-01T00:00:00Z"}],
             c.context
           ) == 0

    assert [] == rows("SELECT id FROM trips WHERE name='invalid planned'")
    assert [] == rows("SELECT command_type FROM job_outbox")
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")

    created =
      hd(data["exports"])
      |> Map.put("name", "restored created points")
      |> Map.put("status", "created")
      |> Map.put("file_name", nil)

    assert Exports.call(ScratchRepo, c.user_id, [created], dir, c.context) == [1, 0]
    assert [["exports.points_created"]] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  test "restore missing or unsafe attachment keeps Rails row and count policy", %{
    c: c,
    data: data,
    dir: dir
  } do
    import = hd(data["imports"])

    missing =
      import
      |> Map.put("name", "missing")
      |> Map.put("file_name", "absent")
      |> Map.put("file_error", "source failure")

    assert Imports.call(ScratchRepo, c.user_id, [missing], dir, c.context) == [1, 0]

    for {filename, index} <- Enum.with_index(["", " ", ".", "..", nil]) do
      item = import |> Map.put("name", "unsafe #{index}") |> Map.put("file_name", filename)
      assert Imports.call(ScratchRepo, c.user_id, [item], dir, c.context) == [1, 0]
    end

    basename =
      import
      |> Map.put("name", "basename")
      |> Map.put("user_id", 123)
      |> Map.update!("file_name", &("../../" <> &1))
      |> Map.put("original_filename", "../../safe.json")
      |> Map.put("file_error", "ignored when file exists")

    assert Imports.call(ScratchRepo, c.user_id, [basename], dir, c.context) == [1, 1]
    assert [["safe.json"]] == rows("SELECT filename FROM active_storage_blobs")
    assert [[c.user_id]] == rows("SELECT user_id FROM imports WHERE name='basename'")

    assert_raise KeyError, fn ->
      Imports.call(
        ScratchRepo,
        c.user_id,
        [Map.put(import, "name", "unknown import") |> Map.put("removed_column", true)],
        dir,
        c.context
      )
    end

    assert File.exists?(Path.join(dir, import["file_name"]))

    export =
      hd(data["exports"]) |> Map.put("name", "missing export") |> Map.put("file_name", "absent")

    assert Exports.call(ScratchRepo, c.user_id, [export], dir, c.context) == [1, 0]
    assert Imports.call(ScratchRepo, c.user_id, [nil, %{"name" => ""}], dir, c.context) == [0, 0]

    assert Exports.call(
             ScratchRepo,
             c.user_id,
             [
               nil,
               %{},
               Map.put(export, "status", "bogus"),
               Map.put(export, "name", "unknown") |> Map.put("removed_column", true)
             ],
             dir,
             c.context
           ) == [0, 0]

    assert Trips.call(
             ScratchRepo,
             c.user_id,
             [nil, %{}, Map.put(hd(data["trips"]), "started_at", nil)],
             c.context
           ) == 0

    assert Imports.call(ScratchRepo, c.user_id, nil, dir, c.context) == [0, 0]
    assert Exports.call(ScratchRepo, c.user_id, nil, dir, c.context) == [0, 0]
    assert Trips.call(ScratchRepo, c.user_id, nil, c.context) == 0

    assert {:error, :synthetic_rollback} =
             ScratchRepo.transaction(fn ->
               assert Imports.call(
                        ScratchRepo,
                        c.user_id,
                        [Map.put(import, "name", "rollback")],
                        dir,
                        c.context
                      ) == [1, 1]

               ScratchRepo.rollback(:synthetic_rollback)
             end)

    assert [] == rows("SELECT id FROM imports WHERE name='rollback'")
    assert [[1]] == rows("SELECT count(*) FROM active_storage_blobs")
    assert length(Path.wildcard(Path.join(c.context.storage.root, "??/??/*"))) == 2
    assert [] == rows("SELECT command_type FROM job_outbox")
    failed_storage = Map.put(c.context, :storage, %{service: "unsupported"})

    assert Imports.call(
             ScratchRepo,
             c.user_id,
             [Map.put(import, "name", "storage failure")],
             dir,
             failed_storage
           ) == [1, 0]

    assert [[1]] == rows("SELECT count(*) FROM imports WHERE name='storage failure'")
  end

  defp utc_timestamps(row) do
    Map.new(row, fn {name, value} ->
      if String.ends_with?(name, "_at") and is_binary(value) do
        {:ok, datetime, _} = DateTime.from_iso8601(value)
        {name, DateTime.to_iso8601(datetime)}
      else
        {name, value}
      end
    end)
  end
end
