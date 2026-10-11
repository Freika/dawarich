defmodule Dawarich.NativeExportDeleteOwnershipTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Accounts.{Principal, Scope}
  alias Dawarich.Exports
  alias Dawarich.Jobs.Ownership

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "on")
    root = Path.join(System.tmp_dir!(), "native-export-owner-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      File.rm_rf!(root)
    end)

    user =
      Dawarich.Test.RailsUser.insert!(
        %{id: 13241, email: "delete-owner@example.invalid"},
        ScratchRepo
      )

    for key <- ~w(command:exports.points command:users.export_data),
        do: Ownership.put!(ScratchRepo, key, :oban)

    %{scope: Scope.for_user(Principal.project(user), "en"), root: root}
  end

  for {name, type, key} <- [
        {"point", 0, "command:exports.points"},
        {"account", 1, "command:users.export_data"}
      ] do
    test "native #{name} export deletion refuses unavailable parent without any effect", c do
      Ownership.put!(ScratchRepo, unquote(key), :sidekiq)

      for attached <- [true, false] do
        {id, path} = export(c, unquote(type), attached)
        before = footprint()
        assert {:error, :not_owned} = Exports.delete(c.scope, id, repo: ScratchRepo)
        assert footprint() == before
        if path, do: assert(File.read!(path) == "synthetic export")
      end
    end
  end

  test "native export deletion holds the effective producer before deletion until commit", c do
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      ScratchRepo.config()[:telemetry_prefix] ++ [:query],
      &__MODULE__.barrier/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    {id, _path} = export(c, 1, true)

    deletion =
      Task.async(fn ->
        Process.put(:native_delete_barrier, true)
        Exports.delete(c.scope, id, repo: ScratchRepo)
      end)

    on_exit(fn -> if Process.alive?(deletion.pid), do: Task.shutdown(deletion, :brutal_kill) end)
    assert_receive {:producer_locked, pid}, 1000
    refute_receive :deletion_effect, 0
    parent = self()

    transfer =
      Task.async(fn ->
        send(parent, :transfer_started)
        Ownership.put!(ScratchRepo, "command:users.export_data", :sidekiq)
      end)

    on_exit(fn -> if Process.alive?(transfer.pid), do: Task.shutdown(transfer, :brutal_kill) end)
    assert_receive :transfer_started
    transfer_ref = transfer.ref
    refute_receive {^transfer_ref, _}, 50
    send(pid, :continue_deletion)
    assert {:ok, :deleted} = Task.await(deletion)
    assert :ok = Task.await(transfer)

    assert [["sidekiq"]] ==
             rows("SELECT owner FROM phoenix.job_owners WHERE key='command:users.export_data'")

    assert [] == rows("SELECT kind FROM phoenix.rails_commands")

    assert [[1]] ==
             rows(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'"
             )
  end

  test "standalone native export deletion keeps the native override for both parent types", c do
    System.put_env("DAWARICH_RAILS", "off")

    for {type, key} <- [{0, "command:exports.points"}, {1, "command:users.export_data"}] do
      Ownership.put!(ScratchRepo, key, :sidekiq)
      {id, _} = export(c, type, true)
      assert {:ok, :deleted} = Exports.delete(c.scope, id, repo: ScratchRepo)
    end

    assert [] == rows("SELECT kind FROM phoenix.rails_commands")

    assert [[2]] ==
             rows(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'"
             )
  end

  def barrier(_event, _measurements, %{query: sql, params: params}, parent) do
    if Process.get(:native_delete_barrier) do
      if String.contains?(sql, "DELETE FROM active_storage_attachments") or
           String.contains?(sql, "DELETE FROM exports"),
         do: send(parent, :deletion_effect)

      if String.contains?(sql, "SELECT key, owner FROM phoenix.job_owners") and
           params == [["command:users.export_data"]] do
        send(parent, {:producer_locked, self()})

        receive do
          :continue_deletion -> :ok
        after
          5000 -> raise "producer barrier timed out"
        end

        Process.delete(:native_delete_barrier)
      end
    end
  end

  defp export(c, type, attached) do
    [[id]] =
      rows(
        "INSERT INTO exports(user_id,name,status,file_format,file_type,created_at,updated_at) VALUES($1,'native.zip',2,2,$2,now(),now()) RETURNING id",
        [c.scope.user.id, type]
      )

    path =
      if attached do
        blob =
          Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "native.zip", "synthetic export")

        rows(
          "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Export',$1,$2,now())",
          [id, blob.id]
        )

        [[key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [blob.id])
        Dawarich.Storage.disk_path(c.root, key)
      end

    {id, path}
  end

  defp footprint do
    for table <-
          ~w(exports active_storage_attachments active_storage_blobs job_outbox phoenix.export_claims phoenix.rails_commands phoenix.upload_receipts phoenix.native_uploads phoenix.export_legacy_artifacts oban.oban_jobs) do
      rows("SELECT row_to_json(t)::text FROM #{table} t ORDER BY row_to_json(t)::text")
    end
  end
end
