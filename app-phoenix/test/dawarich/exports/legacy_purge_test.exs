defmodule Dawarich.Exports.LegacyPurgeTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  alias Dawarich.{Exports, Accounts.Scope, Accounts.Principal}
  @tag :tmp_dir
  test "native legacy export deletion purges only its unshared local artifact after commit", %{
    tmp_dir: root
  } do
    user =
      Dawarich.Test.RailsUser.insert!(
        %{id: 11111, email: "legacy-purge@example.invalid"},
        ScratchRepo
      )

    scope = Scope.for_user(Principal.project(user), "en")
    opts = [repo: ScratchRepo]
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:exports.points", :oban)
    File.mkdir_p!(Path.join(root, "exports"))
    file = Path.join(root, "exports/shared.gpx")
    File.write!(file, "synthetic legacy bytes")
    [first, second] = insert(user.id, ["exports/shared.gpx", "exports/shared.gpx"])
    assert {:ok, :deleted} = Exports.delete(scope, first, opts)
    [intent] = intents()
    assert File.read!(file) == "synthetic legacy bytes"

    assert_raise ArgumentError, fn ->
      ScratchRepo.transaction(fn ->
        apply(Dawarich.Exports.LegacyPurgeWorker, :run, [ScratchRepo, intent, [root: root]])
      end)
    end

    assert :ok =
             apply(Dawarich.Exports.LegacyPurgeWorker, :run, [ScratchRepo, intent, [root: root]])

    assert File.read!(file) == "synthetic legacy bytes"
    assert {:ok, :deleted} = Exports.delete(scope, second, opts)
    [^intent, outcome] = intents()

    assert :ok =
             apply(Dawarich.Exports.LegacyPurgeWorker, :run, [ScratchRepo, outcome, [root: root]])

    refute File.exists?(file)

    assert :ok =
             apply(Dawarich.Exports.LegacyPurgeWorker, :run, [ScratchRepo, outcome, [root: root]])
  end

  @tag :tmp_dir
  test "unsafe legacy export paths and symlink parents cannot remove outside artifacts", %{
    tmp_dir: root
  } do
    user =
      Dawarich.Test.RailsUser.insert!(
        %{id: 11112, email: "legacy-safety@example.invalid"},
        ScratchRepo
      )

    scope = Scope.for_user(Principal.project(user), "en")
    outside = root <> "-outside"
    File.mkdir_p!(outside)
    File.write!(Path.join(outside, "kept.gpx"), "outside bytes")
    on_exit(fn -> File.rm_rf!(outside) end)
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:exports.points", :oban)

    for url <- ["../kept.gpx", "https://example.invalid/kept.gpx", "exports/../kept.gpx"] do
      [id] = insert(user.id, [url])
      assert {:error, :unsafe_legacy_path} = Exports.delete(scope, id, repo: ScratchRepo)
      assert rows("SELECT id FROM exports WHERE id=$1", [id]) == [[id]]
    end

    File.mkdir_p!(Path.join(root, "exports"))
    File.ln_s!(outside, Path.join(root, "exports/escape"))
    [id] = insert(user.id, ["exports/escape/kept.gpx"])
    assert {:ok, :deleted} = Exports.delete(scope, id, repo: ScratchRepo)
    [intent] = intents()

    assert {:error, :unsafe_legacy_path} =
             apply(Dawarich.Exports.LegacyPurgeWorker, :run, [ScratchRepo, intent, [root: root]])

    assert File.read!(Path.join(outside, "kept.gpx")) == "outside bytes"
  end

  @tag :tmp_dir
  test "restored export URLs never authorize deletion of unrelated public files", %{tmp_dir: root} do
    user =
      Dawarich.Test.RailsUser.insert!(
        %{id: 11113, email: "restored-path@example.invalid"},
        ScratchRepo
      )

    scope = Scope.for_user(Principal.project(user), "en")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:exports.points", :oban)
    File.mkdir_p!(Path.join(root, "exports"))

    for {url, name} <- [{"/404.html", "error-page"}, {"exports/other-owner.gpx", "other-owner"}] do
      file = Path.join(root, String.trim_leading(url, "/"))
      File.write!(file, "unrelated public bytes")
      data = [%{"name" => name, "file_format" => "gpx", "status" => "completed", "url" => url}]
      context = %{now: "2026-10-10 12:00:00", locale: "en"}

      assert [1, 0] =
               Dawarich.UserData.Restore.Exports.call(ScratchRepo, user.id, data, root, context)

      [[id]] = rows("SELECT id FROM exports WHERE user_id=$1 AND name=$2", [user.id, name])

      rows(
        "INSERT INTO phoenix.export_legacy_artifacts(identity,export_id,user_id,path) VALUES($1,$2,$3,$4)",
        [Ecto.UUID.generate(), id, user.id + 1, "exports/unrelated.gpx"]
      )

      assert {:ok, :deleted} = Exports.delete(scope, id, repo: ScratchRepo)

      assert :ok =
               Dawarich.Exports.LegacyPurgeWorker.run(
                 ScratchRepo,
                 %{"path" => String.trim_leading(url, "/")},
                 root: root
               )

      for intent <- intents() do
        assert :ok = Dawarich.Exports.LegacyPurgeWorker.run(ScratchRepo, intent, root: root)
      end

      assert File.read!(file) == "unrelated public bytes"
    end

    assert [] == intents()
  end

  defp insert(user, urls) do
    for url <- urls do
      [[id]] =
        rows(
          "INSERT INTO exports(user_id,name,status,file_format,file_type,url,created_at,updated_at) VALUES($1,'legacy.gpx',2,1,0,$2,now(),now()) RETURNING id",
          [user, url]
        )

      if String.starts_with?(url, "exports/") and not String.contains?(url, "..") do
        rows(
          "INSERT INTO phoenix.export_legacy_artifacts(identity,export_id,user_id,path) VALUES($1,$2,$3,$4)",
          [Ecto.UUID.generate(), id, user, url]
        )
      end

      id
    end
  end

  defp intents,
    do:
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.LegacyPurgeWorker' ORDER BY id"
      )
      |> Enum.map(&hd/1)
end
