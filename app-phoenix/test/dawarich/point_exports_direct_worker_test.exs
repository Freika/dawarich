defmodule Dawarich.PointExportsDirectWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.{PointExports, ScratchRepo}
  alias Dawarich.Exports.PointsWorker
  alias Dawarich.Jobs.{Dispatch, Ownership}
  @oban Dawarich.DirectExportTestOban

  test "direct Phoenix command dispatches and writes NY GPX without a reverse table" do
    root = Path.join(System.tmp_dir!(), "direct-export-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    backend = System.get_env("STORAGE_BACKEND")
    System.delete_env("STORAGE_BACKEND")
    rows("ALTER TABLE phoenix.rails_commands RENAME TO direct_saved_rails_commands")

    on_exit(fn ->
      rows("ALTER TABLE phoenix.direct_saved_rails_commands RENAME TO rails_commands")
      File.rm_rf!(root)
      if backend, do: System.put_env("STORAGE_BACKEND", backend)
    end)

    [[id]] =
      rows(
        "INSERT INTO users (email, created_at, updated_at) VALUES ('direct-worker@example.test', now(), now()) RETURNING id"
      )

    rows(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) VALUES ($1, 1774748800, ST_SetSRID(ST_MakePoint(13.4, 0.00005),4326)::geography, now(), now())",
      [id]
    )

    Ownership.put!(ScratchRepo, "command:exports.points", :oban)
    user = %{id: id, settings: %{"timezone" => "America/New_York"}}

    {:ok, export} =
      PointExports.parse(%{
        "start_at" => "2026-03-29 00:00:00 UTC",
        "end_at" => "2026-03-30 00:00:00 UTC",
        "file_format" => "gpx"
      })

    assert {:ok, export_id} = PointExports.create(export, user, "en", ScratchRepo)

    rows(
      "UPDATE users SET settings = '{\"timezone\":\"Pacific/Auckland\"}'::jsonb WHERE id = $1",
      [id]
    )

    start_oban(@oban)
    assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{dispatched: 1}
    assert [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args["export_id"] == export_id
    assert args["time_zone"] == "America/New_York"
    assert File.cd!(root, fn -> perform_job(PointsWorker, args) end) == :ok
    assert [[2]] = rows("SELECT status FROM exports WHERE id = $1", [export_id])
    [path] = Path.wildcard(Path.join(root, "storage/??/??/*"))
    assert {:ok, [{_, xml}]} = :zip.unzip(to_charlist(path), [:memory])
    assert xml =~ "<time>2026-03-28T21:46:40-04:00</time>"
  end
end
