defmodule Dawarich.UserData.RestoreParserTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Restore

  @tag :tmp_dir
  test "parser failures roll back and preserve Rails service notification text", %{tmp_dir: dir} do
    for name <- ~w(invalid_jsonl_root invalid_jsonl_monthly invalid_manifest) do
      reset!(ScratchRepo)
      rows("DELETE FROM countries WHERE id=988991")

      rows(
        "TRUNCATE places,areas,tags,taggings,visits,tracks,track_segments,digests,points_raw_data_archives CASCADE"
      )

      c = UserDataSeeds.seed!(name, ScratchRepo)

      try do
        Restore.call(ScratchRepo, c.user_id, c.archive_path, Map.put(c.context, :temp_dir, dir))
        flunk("parser accepted invalid archive")
      rescue
        error -> assert Exception.message(error) == c.expected["error"]["message"]
      end

      assert rows("SELECT title,content,kind FROM notifications ORDER BY id") ==
               Enum.map(c.expected["notifications"], &[&1["title"], &1["content"], 2])

      assert [] == rows("SELECT id FROM points")
      assert [] == rows("SELECT id FROM areas")
      assert [] == rows("SELECT id FROM imports")

      assert [
               [
                 %{
                   "timezone" => "UTC",
                   "locale" => "en",
                   "gps_filtering_enabled" => false,
                   "retained" => "yes"
                 }
               ]
             ] == rows("SELECT settings FROM users WHERE id=$1", [c.user_id])

      assert [] == File.ls!(dir)
    end
  end
end
