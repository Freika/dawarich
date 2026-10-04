defmodule Dawarich.UserData.RestoreTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Restore

  setup do
    clean()
    :ok
  end

  @tag :tmp_dir
  test "v1 and v2 restore order and success stats equal Rails roundtrip", %{tmp_dir: dir} do
    for name <- ["v1", "v1_reversed", "v2"] do
      Dawarich.JobsCase.reset!(ScratchRepo)
      clean()
      c = UserDataSeeds.seed!(name, ScratchRepo)
      context = Map.put(c.context, :temp_dir, dir)
      assert Restore.call(ScratchRepo, c.user_id, c.archive_path, context) == c.expected["result"]

      assert [[c.expected["settings"]]] ==
               rows("SELECT settings FROM users WHERE id=$1", [c.user_id])

      assert notes(c.user_id) ==
               Enum.map(c.expected["notifications"], &Map.take(&1, ~w(title content kind)))

      assert [[3, 3, 3]] == rows("SELECT count(*),count(import_id),count(visit_id) FROM points")
      assert [[1, 3]] == rows("SELECT count(DISTINCT source_id),count(source_id) FROM points")

      assert [[c.expected["result"]["files_restored"]]] ==
               rows("SELECT count(*) FROM active_storage_attachments")

      assert [[0, 0]] == rows("SELECT raw_points,doubles FROM imports")

      assert [[1]] ==
               rows(
                 "SELECT count(*) FROM visits v JOIN places p ON p.id=v.place_id AND p.user_id=v.user_id"
               )

      if name == "v2" do
        repeat =
          Path.expand("../../fixtures/user_data/capture.json", __DIR__)
          |> File.read!()
          |> Jason.decode!()
          |> get_in(["restores", "v2_repeat"])

        assert Restore.call(ScratchRepo, c.user_id, c.archive_path, context) == repeat["result"]

        assert List.last(notes(c.user_id)) ==
                 List.last(repeat["notifications"]) |> Map.take(~w(title content kind))
      end

      assert [] == File.ls!(dir)
    end

    Dawarich.JobsCase.reset!(ScratchRepo)
    clean()
    c = UserDataSeeds.seed!("v2", ScratchRepo)

    entries = %{
      "manifest.json" => Jason.encode!(%{"format_version" => 2}),
      "settings.jsonl" => "false\n"
    }

    path = zip!(dir, entries)
    result = Restore.call(ScratchRepo, c.user_id, path, c.context)
    assert result["settings_updated"] == true
    assert [["yes"]] == rows("SELECT settings->>'retained' FROM users WHERE id=$1", [c.user_id])
    File.rm!(path)
  end

  @tag :tmp_dir
  test "restore transaction failure rolls back data but keeps failure notification", %{
    tmp_dir: dir
  } do
    c = UserDataSeeds.seed!("transaction_error", ScratchRepo)
    context = Map.put(c.context, :temp_dir, dir)

    assert_raise ArgumentError, c.expected["error"]["message"], fn ->
      Restore.call(ScratchRepo, c.user_id, c.archive_path, context)
    end

    assert notes(c.user_id) ==
             Enum.map(c.expected["notifications"], &Map.take(&1, ~w(title content kind)))

    assert [[c.expected["settings"]]] ==
             rows("SELECT settings FROM users WHERE id=$1", [c.user_id])

    assert [] == rows("SELECT id FROM tags")
    assert [] == rows("SELECT id FROM points")
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    assert [] == File.ls!(dir)
  end

  @tag :tmp_dir
  test "post-commit anomaly failure cannot undo restored data", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("v2", ScratchRepo)

    filter = fn repo, user, first, last, _opts ->
      refute repo.in_transaction?()
      assert [[3]] == rows("SELECT count(*) FROM points WHERE user_id=$1", [user])
      assert first < last
      repo.query!("SELECT 1/0", [], log: false)
    end

    report = fn error, message -> send(self(), {:reported, error.postgres[:code], message}) end
    context = c.context |> Map.put(:temp_dir, dir) |> Map.put(:report, report)

    assert Restore.call(ScratchRepo, c.user_id, c.archive_path, context, filter: filter) ==
             c.expected["result"]

    assert_received {:reported, :division_by_zero, "Anomaly filtering failed after data import"}
    assert [[3]] == rows("SELECT count(*) FROM points")
    assert List.last(notes(c.user_id))["title"] == "Data import completed"
    assert [] == File.ls!(dir)

    rows(
      "UPDATE users SET settings=jsonb_set(settings,'{gps_filtering_enabled}','true') WHERE id=$1",
      [c.user_id]
    )

    rows("UPDATE points SET accuracy=20000 WHERE user_id=$1", [c.user_id])
    assert Restore.filter(ScratchRepo, c.user_id, c.context) == 3
    assert [[3]] == rows("SELECT count(*) FROM points WHERE anomaly=true")
  end

  @tag :tmp_dir
  test "missing archive format notifies and returns nil", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("missing", ScratchRepo)

    assert Restore.call(
             ScratchRepo,
             c.user_id,
             c.archive_path,
             Map.put(c.context, :temp_dir, dir)
           ) == nil

    assert notes(c.user_id) ==
             Enum.map(
               c.expected["service"]["notifications"],
               &Map.take(&1, ~w(title content kind))
             )

    assert [] == File.ls!(dir)
  end

  @tag :tmp_dir
  test "unsupported archive version notifies and raises", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("version3", ScratchRepo)

    assert_raise RuntimeError, c.expected["service"]["error"]["message"], fn ->
      Restore.call(ScratchRepo, c.user_id, c.archive_path, Map.put(c.context, :temp_dir, dir))
    end

    assert notes(c.user_id) ==
             Enum.map(
               c.expected["service"]["notifications"],
               &Map.take(&1, ~w(title content kind))
             )

    assert [] == File.ls!(dir)
  end

  defp clean do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )
  end

  defp notes(user) do
    rows("SELECT title,content,kind FROM notifications WHERE user_id=$1 ORDER BY id", [user])
    |> Enum.map(fn [title, content, kind] ->
      %{"title" => title, "content" => content, "kind" => Enum.at(~w(info warning error), kind)}
    end)
  end

  defp zip!(dir, entries) do
    path = Path.join(dir, "input.zip")

    {:ok, _} =
      :zip.create(
        String.to_charlist(path),
        Enum.map(entries, fn {name, bytes} -> {String.to_charlist(name), bytes} end)
      )

    path
  end
end
