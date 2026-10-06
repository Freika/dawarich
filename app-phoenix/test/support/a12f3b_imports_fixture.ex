defmodule Dawarich.A12f3bImportsFixture do
  import Dawarich.JobsCase
  alias Dawarich.ScratchRepo

  def setup do
    c = Dawarich.ImportLeaseFixture.create()
    root = Path.join(System.tmp_dir!(), "reverse-imports-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    old = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    configured = Application.fetch_env(:dawarich, :imports_services)

    Application.put_env(:dawarich, :imports_services, %{
      "local" => %{service: "local", root: root}
    })

    ExUnit.Callbacks.on_exit(fn ->
      if old, do: System.put_env("DAWARICH_RAILS", old), else: System.delete_env("DAWARICH_RAILS")

      case configured do
        {:ok, value} -> Application.put_env(:dawarich, :imports_services, value)
        :error -> Application.delete_env(:dawarich, :imports_services)
      end

      File.rm_rf!(root)
    end)

    Map.merge(c, %{
      root: root,
      context: %{
        repo: ScratchRepo,
        zone: "Europe/Berlin",
        locale: "en",
        now: ~U[2026-01-01 12:00:00Z]
      }
    })
  end

  def blob(c, name, bytes, attachment) do
    blob = Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, name, bytes)

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,$2,$3,now())",
      [c.import.id, attachment, blob.id]
    )

    [[key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [blob.id])
    Map.put(blob, :key, key)
  end

  def destroy(c) do
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.destroy", :oban)
    args = Map.drop(c.job.args, ["time_zone"])

    rows(
      "UPDATE oban.oban_jobs SET worker='Dawarich.Imports.DestroyWorker',args=$2 WHERE id=$1",
      [c.job.id, args]
    )

    %{c | job: %{c.job | args: args}}
  end

  def with_destroy(c, fun), do: Dawarich.Imports.DestroyLease.with_import(ScratchRepo, c.job, fun)

  def workers,
    do:
      rows("SELECT worker FROM oban.oban_jobs WHERE state<>'executing' ORDER BY id")
      |> List.flatten()

  def reverse,
    do: rows("SELECT kind FROM phoenix.rails_commands WHERE kind LIKE 'imports.%' ORDER BY id")
end
