defmodule Dawarich.UploadsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{Storage, Uploads}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser

  setup do
    user = RailsUser.insert!(%{id: 10842, email: "upload-owner@example.invalid"}, ScratchRepo)
    other = RailsUser.insert!(%{id: 10843, email: "upload-other@example.invalid"}, ScratchRepo)
    root = Path.join(System.tmp_dir!(), "owned-upload-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      scope: Scope.for_user(user, "en"),
      other: Scope.for_user(other, "en"),
      policy: %{repo: ScratchRepo, storage: %{service: "local", root: root}, kind: :imports},
      root: root
    }
  end

  defp reserve(c, bytes \\ "synthetic") do
    attrs = %{
      filename: "synthetic.gpx",
      byte_size: byte_size(bytes),
      checksum: Base.encode64(:crypto.hash(:md5, bytes)),
      content_type: "application/gpx+xml"
    }

    assert {:ok, ref} = Uploads.reserve(c.scope, attrs, c.policy)

    [[blob, key]] =
      rows(
        "SELECT b.id,b.key FROM active_storage_blobs b JOIN phoenix.native_uploads u ON u.blob_id=b.id WHERE u.reference=$1",
        [ref]
      )

    path = Storage.disk_path(c.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    {ref, blob, path}
  end

  test "cancel and claim serialize so exactly one owns a pending upload", c do
    {ref, _, _} = reserve(c)
    parent = self()

    first =
      Task.async(fn ->
        Uploads.claim(c.scope, [ref], :imports,
          repo: ScratchRepo,
          services: %{"local" => c.policy.storage},
          after_lock: fn ->
            send(parent, {:locked, self()})

            receive do
              :continue -> :ok
            after
              5000 -> raise "claim barrier timed out"
            end
          end
        )
      end)

    assert_receive {:locked, pid}

    second =
      Task.async(fn ->
        send(parent, :cancelling)
        Uploads.cancel(c.scope, ref, repo: ScratchRepo)
      end)

    assert_receive :cancelling
    second_ref = second.ref
    refute_receive {^second_ref, _}, 50
    send(pid, :continue)
    assert {:ok, [_]} = Task.await(first)
    assert {:error, :claimed} = Task.await(second)

    assert [["claimed"]] =
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [ref])
  end

  test "expired abandoned uploads are purged once after worker restart", c do
    {ref, blob, path} = reserve(c)

    rows(
      "UPDATE phoenix.native_uploads SET expires_at=timezone('UTC',now())-interval '1 second' WHERE reference=$1",
      [ref]
    )

    {live, _, live_path} = reserve(c)
    assert {:ok, 1} = Uploads.sweep(repo: ScratchRepo)
    assert {:ok, 0} = Uploads.sweep(repo: ScratchRepo)

    assert [[args]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.CleanupWorker' AND args->>'reference'=$1",
               [ref]
             )

    assert :ok =
             apply(Dawarich.Uploads.CleanupWorker, :run, [
               args,
               [repo: ScratchRepo, services: %{"local" => c.policy.storage}]
             ])

    assert :ok =
             apply(Dawarich.Uploads.CleanupWorker, :run, [
               args,
               [repo: ScratchRepo, services: %{"local" => c.policy.storage}]
             ])

    refute File.exists?(path)
    assert [] = rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob])

    assert [["purged"]] =
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [ref])

    assert [["pending"]] =
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [live])

    assert File.exists?(live_path)
  end

  test "foreign guest attached and purged receipts cannot be claimed or cancelled", c do
    {ref, blob, _} = reserve(c)
    opts = [repo: ScratchRepo, services: %{"local" => c.policy.storage}]
    assert {:error, :not_found} = Uploads.cancel(c.other, ref, opts)
    assert {:error, :not_found} = Uploads.claim(c.other, [ref], :imports, opts)
    assert {:error, :stale_session} = Uploads.cancel(nil, ref, opts)
    assert {:error, :stale_session} = Uploads.claim(nil, [ref], :imports, opts)

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Export',42,$1,now())",
      [blob]
    )

    assert {:error, :attached} = Uploads.cancel(c.scope, ref, opts)
    assert {:error, :attached} = Uploads.claim(c.scope, [ref], :imports, opts)
    rows("DELETE FROM active_storage_attachments WHERE blob_id=$1", [blob])
    assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref, opts)
    assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref, opts)
    assert {:error, :cancelled} = Uploads.claim(c.scope, [ref], :imports, opts)
  end

  test "stored size or checksum mismatch refuses the entire claim without publication", c do
    {first, _, _} = reserve(c)
    {bad, _, path} = reserve(c)
    File.write!(path, "corrupt")

    assert {:error, :invalid_object} =
             Uploads.claim(c.scope, [first, bad], :imports,
               repo: ScratchRepo,
               services: %{"local" => c.policy.storage}
             )

    assert [[2]] = rows("SELECT count(*) FROM phoenix.native_uploads WHERE state='pending'")
    assert [] = rows("SELECT event_id FROM job_outbox")
  end

  test "cleanup refuses an attached export and retains a late PUT tombstone until target expiry",
       c do
    {ref, blob, path} = reserve(c)

    rows(
      "UPDATE phoenix.native_uploads SET target_until=timezone('UTC',now())+interval '5 minutes' WHERE reference=$1",
      [ref]
    )

    assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref, repo: ScratchRepo)
    args = %{"reference" => ref}
    opts = [repo: ScratchRepo, services: %{"local" => c.policy.storage}]
    assert {:snooze, _} = apply(Dawarich.Uploads.CleanupWorker, :run, [args, opts])
    [[metadata]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob])
    assert Dawarich.Storage.NativePurge.pending?(metadata)
    File.write!(path, "late PUT")

    rows(
      "UPDATE phoenix.native_uploads SET target_until=timezone('UTC',now())-interval '1 second' WHERE reference=$1",
      [ref]
    )

    assert :ok = apply(Dawarich.Uploads.CleanupWorker, :run, [args, opts])
    refute File.exists?(path)
    {ref, blob, path} = reserve(c)

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Export',43,$1,now())",
      [blob]
    )

    assert {:error, :attached} = Uploads.cancel(c.scope, ref, repo: ScratchRepo)
    assert :ok = apply(Dawarich.Uploads.CleanupWorker, :run, [%{"reference" => ref}, opts])
    assert File.exists?(path)
  end

  test "reservation budgets serialize concurrent quota checks and reject revoked identity", c do
    policy = Map.put(c.policy, :max_entries, 1)

    tasks =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              Uploads.reserve(
                c.scope,
                %{
                  filename: "synthetic.gpx",
                  byte_size: 9,
                  checksum: Base.encode64(:crypto.hash(:md5, "synthetic")),
                  content_type: "application/gpx+xml"
                },
                policy
              )
            end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, :limit} in results
    rows("UPDATE users SET encrypted_password='revoked' WHERE id=10842")

    assert {:error, :stale_session} =
             Uploads.reserve(c.scope, %{filename: "x", byte_size: 9}, policy)
  end

  test "legacy receipt fetch refuses a cancelled upload tombstone", c do
    {ref, blob, _} = reserve(c)
    token = Dawarich.RailsMessages.blob_id(blob)
    assert {:ok, _} = Dawarich.Imports.Uploads.fetch(ScratchRepo, token)
    assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref, repo: ScratchRepo)
    assert {:error, :not_found} = Dawarich.Imports.Uploads.fetch(ScratchRepo, token)
  end

  test "prepared legacy import cannot attach after upload cancellation", c do
    {ref, blob, _} = reserve(c)

    assert {:ok, file} =
             Dawarich.Imports.Uploads.fetch(ScratchRepo, Dawarich.RailsMessages.blob_id(blob))

    item = %{
      blob: file,
      name: "synthetic.gpx",
      source: 4,
      metadata: %{},
      upload_user_id: c.scope.user.id
    }

    assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref, repo: ScratchRepo)

    assert {:error, :not_found} =
             ScratchRepo.transaction(fn ->
               Dawarich.Imports.UploadRecords.insert!(ScratchRepo, c.scope.user, item, :oban)
             end)

    assert [] = rows("SELECT id FROM imports")
    assert [] = rows("SELECT event_id FROM job_outbox")
  end
end
