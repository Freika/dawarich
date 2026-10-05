defmodule Dawarich.UserData.FixturesTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    :ok
  end

  test "user-data fixture seeds own rows and synthetic portable storage" do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    assert c.user_id == 988_001
    assert [[3]] == rows("SELECT count(*) FROM points WHERE user_id=$1", [c.user_id])
    assert [[1]] == rows("SELECT count(*) FROM tracks WHERE user_id=$1", [c.user_id])
    assert [[1]] == rows("SELECT count(*) FROM tags WHERE user_id=$1", [c.user_id])
    assert [[3]] == rows("SELECT count(*) FROM active_storage_attachments")
    assert c.expected["manifest"]["counts"]["exports"] == 2
    assert {:ok, entries} = :zip.extract(String.to_charlist(c.archive_path), [:memory])
    assert {~c"settings.jsonl", settings} = List.keyfind(entries, ~c"settings.jsonl", 0)
    assert Jason.decode!(settings)["timezone"] == "UTC"

    [[key]] =
      rows("SELECT key FROM active_storage_blobs WHERE content_type='application/octet-stream'")

    assert File.read!(Dawarich.Storage.disk_path(c.context.storage.root, key)) ==
             Jason.decode!(File.read!("test/fixtures/a12b/crypto.json"))["archives"]["written"]
             |> hd()
             |> Map.fetch!("message")
  end
end
