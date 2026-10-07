defmodule Dawarich.Exports.PurgeOwnershipTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Jobs.{Ownership, Registry}
  alias Dawarich.Exports.{Delete, PurgeWorker}

  setup do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        ScratchRepo.config()[:telemetry_prefix] ++ [:query],
        &__MODULE__.capture_query/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    old = System.get_env("DAWARICH_RAILS")
    root = Path.join(System.tmp_dir!(), "export-purge-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)

    on_exit(fn ->
      if old, do: System.put_env("DAWARICH_RAILS", old), else: System.delete_env("DAWARICH_RAILS")
      File.rm_rf!(root)
    end)

    [[user]] =
      rows("INSERT INTO users(email,created_at,updated_at) VALUES($1,now(),now()) RETURNING id", [
        "purge-#{Ecto.UUID.generate()}@example.test"
      ])

    for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)

    %{
      user: user,
      root: root,
      services: %{default: "local", services: %{"local" => %{service: "local", root: root}}}
    }
  end

  @tag a12f3b_case: "R12k02"
  test "native export purge reaches storage terminal effects in coexistence and standalone", c do
    for mode <- ["on", "off"], type <- [0, 1] do
      System.put_env("DAWARICH_RAILS", mode)

      assert Enum.all?(Registry.entries(), fn e ->
               rows("SELECT owner FROM phoenix.job_owners WHERE key=$1", [e.key]) == [["oban"]]
             end)

      {id, blob, key} = attached(c, type)
      shared = Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "shared.zip", "shared")

      [[other]] =
        rows(
          "INSERT INTO exports(user_id,name,status,file_format,file_type,created_at,updated_at) VALUES($1,'other.zip',2,2,$2,now(),now()) RETURNING id",
          [c.user, type]
        )

      for record <- [id, other], do: attach(record, shared.id, "shared")

      assert {:ok, :deleted} == Delete.call(ScratchRepo, c.user, id)
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      assert [] == rows("SELECT id FROM exports WHERE id=$1", [id])

      assert [] ==
               rows(
                 "SELECT id FROM active_storage_attachments WHERE record_type='Export' AND record_id=$1",
                 [id]
               )

      assert [[args]] =
               rows(
                 "SELECT args FROM oban.oban_jobs WHERE worker=$1 AND args->'blob_ids' @> $2::jsonb",
                 ["Dawarich.Exports.PurgeWorker", [blob.id]]
               )

      assert [blob.id] == Enum.map(args["objects"], & &1["blob_id"])

      assert [[metadata]] =
               rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])

      assert Dawarich.Storage.NativePurge.pending?(metadata)

      assert [[shared_metadata]] =
               rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [shared.id])

      refute Dawarich.Storage.NativePurge.pending?(shared_metadata)
      path = Dawarich.Storage.disk_path(c.root, key)
      assert File.read!(path) == "synthetic export"
      File.rm!(path)
      File.mkdir_p!(path)

      assert {:error, {:storage_delete, _}} =
               PurgeWorker.run(args, repo: ScratchRepo, services: c.services)

      assert [[blob.id]] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
      File.rmdir!(path)
      File.write!(path, "synthetic export")
      assert :ok == PurgeWorker.run(args, repo: ScratchRepo, services: c.services)
      assert :ok == PurgeWorker.run(args, repo: ScratchRepo, services: c.services)
      refute File.exists?(path)
      assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
      assert [[shared.id]] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [shared.id])
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    end
  end

  @tag a12f3b_case: "R12parents"
  test "export purge locks the actual parent and retains byte-identical Rails hand-back", c do
    for type <- [0, 1], owner <- [:oban, :sidekiq], mode <- ["on", "off"] do
      System.put_env("DAWARICH_RAILS", mode)
      key = if type == 0, do: "command:exports.points", else: "command:users.export_data"
      other = if type == 0, do: "command:users.export_data", else: "command:exports.points"
      Ownership.put!(ScratchRepo, key, owner, pinned: true)

      Ownership.put!(ScratchRepo, other, if(owner == :oban, do: :sidekiq, else: :oban),
        pinned: true
      )

      {id, blob, storage_key} = attached(c, type)
      assert {:ok, :deleted} == Delete.call(ScratchRepo, c.user, id)

      reverse =
        rows(
          "SELECT kind,payload::text FROM phoenix.rails_commands WHERE payload->>'export_id'=$1",
          [to_string(id)]
        )

      jobs =
        rows(
          "SELECT args FROM oban.oban_jobs WHERE worker=$1 AND args->'blob_ids' @> $2::jsonb",
          ["Dawarich.Exports.PurgeWorker", [blob.id]]
        )

      if mode == "on" and owner == :sidekiq do
        assert [
                 [
                   "exports.purge",
                   ~s({"user_id": #{c.user}, "blob_ids": [#{blob.id}], "export_id": #{id}})
                 ]
               ] == reverse

        assert [] == jobs
        expected = ~s({"blob_ids":[#{blob.id}],"export_id":#{id},"user_id":#{c.user}})
        assert_receive {:purge_payload, ^expected}

        assert [["{}"]] ==
                 rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])

        assert File.read!(Dawarich.Storage.disk_path(c.root, storage_key)) == "synthetic export"
      else
        assert [] == reverse
        assert [[args]] = jobs
        assert :ok == PurgeWorker.run(args, repo: ScratchRepo, services: c.services)
        assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
      end
    end
  end

  def capture_query(_event, _measurements, %{params: ["exports.purge", bytes]}, pid),
    do: send(pid, {:purge_payload, bytes})

  def capture_query(_event, _measurements, _metadata, _pid), do: :ok

  defp attached(c, type) do
    [[id]] =
      rows(
        "INSERT INTO exports(user_id,name,status,file_format,file_type,created_at,updated_at) VALUES($1,'synthetic.zip',2,2,$2,now(),now()) RETURNING id",
        [c.user, type]
      )

    blob =
      Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "synthetic.zip", "synthetic export")

    attach(id, blob.id, "file")
    [[key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [blob.id])
    {id, blob, key}
  end

  defp attach(id, blob, name),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES($1,'Export',$2,$3,now())",
        [name, id, blob]
      )
end
