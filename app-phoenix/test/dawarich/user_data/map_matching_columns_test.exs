defmodule Dawarich.UserData.MapMatchingColumnsTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.{Export, Restore}
  alias Dawarich.UserData.Export.{Files, Tracks}

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places,areas,tags,taggings,visits,tracks,track_segments,digests,points_raw_data_archives CASCADE"
    )

    :ok
  end

  @tag :tmp_dir
  test "map matching Track export bytes and old and new archive restore policy equal Rails", %{
    tmp_dir: dir
  } do
    corpus = corpus()
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    secret = File.read!("test/fixtures/rails_cookies.json") |> Jason.decode!()

    context =
      c.context
      |> Map.put(
        :archive_key,
        Dawarich.RawData.ArchiveFormat.key(%{}, secret["rails_test_secret"])
      )
      |> Map.put(:application_zone, "Europe/Berlin")
      |> Files.context(dir)

    archive = Export.write(ScratchRepo, c.user_id, dir, context)
    assert {:ok, members} = :zip.unzip(String.to_charlist(archive.path), [:memory])
    actual = Map.new(members, fn {name, bytes} -> {List.to_string(name), bytes} end)
    expected = Map.merge(UserDataSeeds.entries("export_UTC"), corpus["exports"]["UTC"])
    assert actual == expected

    for zone <- ["UTC", "Europe/Berlin", "America/New_York"] do
      context = %{c.context | zone: zone}
      [entry] = Tracks.write(ScratchRepo, c.user_id, dir, context)
      assert File.read!(entry.path) == corpus["exports"][zone][entry.name]

      for matched <- corpus["matched"][zone] do
        rows(
          "UPDATE tracks t SET (map_matched_at,map_matching_data,map_matching_input_digest,map_matching_status,matched_path)=(r.map_matched_at,r.map_matching_data,r.map_matching_input_digest,r.map_matching_status,r.matched_path) FROM jsonb_populate_record(NULL::tracks,$1::jsonb) r WHERE t.user_id=$2",
          [matched["seed"], c.user_id]
        )

        [entry] = Tracks.write(ScratchRepo, c.user_id, dir, context)
        assert File.read!(entry.path) == matched["bytes"]
      end

      rows(
        "UPDATE tracks SET map_matched_at=NULL,map_matching_data='{}',map_matching_input_digest=NULL,map_matching_status=NULL,matched_path=NULL WHERE user_id=$1",
        [c.user_id]
      )
    end

    restore_archives(dir, corpus)
  end

  defp restore_archives(dir, corpus) do
    reset!(ScratchRepo)
    c = UserDataSeeds.seed!("v2", ScratchRepo)

    keys =
      ~w(map_matched_at map_matching_data map_matching_input_digest map_matching_status matched_path)

    for {name, capture} <- Enum.sort(corpus["restores"]) do
      rows("DELETE FROM track_segments")
      rows("DELETE FROM tracks")
      path = Path.join(dir, name <> ".zip")

      members =
        Enum.map(capture["entries"], fn {name, bytes} -> {String.to_charlist(name), bytes} end)

      assert {:ok, _} = :zip.create(String.to_charlist(path), members)
      assert Restore.call(ScratchRepo, c.user_id, path, c.context) == capture["result"]

      user_id = c.user_id

      assert [[restored, "LINESTRING(12.4 51.3,12.5 51.4)", ^user_id]] =
               rows("SELECT to_jsonb(t),ST_AsText(original_path),user_id FROM tracks t")

      assert Map.take(restored, keys) == Map.take(capture["track"], keys)
      assert restored["distance"] == capture["track"]["distance"]

      assert [[2, 0, 1]] ==
               rows("SELECT transportation_mode,start_index,end_index FROM track_segments")

      File.rm!(path)
    end
  end

  defp corpus,
    do: File.read!("test/fixtures/user_data/map_matching_columns.json") |> Jason.decode!()
end
