defmodule Dawarich.NativeDerivativePurgeTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Imports, Storage, Uploads}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Exports.PurgeWorker

  setup do
    user = Dawarich.Test.RailsUser.insert!(%{id: 13231, email: "derivative@example.invalid"})
    root = Path.join(System.tmp_dir!(), "derivative-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.process_gpx", :oban)
    %{scope: Scope.for_user(user, "en"), storage: %{service: "local", root: root}}
  end

  test "cleanup before shared purge preserves durable variant and preview deletion", c do
    for kind <- [:variant, :preview] do
      {ref, parent, child, args} = graph(c, kind)
      assert :ok = Dawarich.Uploads.CleanupWorker.run(%{"reference" => ref}, opts(c))
      assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [parent.id])
      assert File.exists?(path(c, child))
      assert :ok = PurgeWorker.run(args, opts(c))
      removed(c, child)
    end
  end

  test "parent DELETE failure retries every independently captured derivative", c do
    for kind <- [:variant, :preview] do
      {_ref, parent, child, args} = graph(c, kind)
      block(c, parent)
      assert {:error, {:storage_delete, :eperm}} = PurgeWorker.run(args, opts(c))
      unblock(c, parent)
      assert :ok = PurgeWorker.run(args, opts(c))
      removed(c, parent)
      removed(c, child)
    end
  end

  test "child DELETE failure after parent fencing retries its exact identity", c do
    for kind <- [:variant, :preview] do
      {_ref, parent, child, args} = graph(c, kind)
      block(c, child)
      assert {:error, {:storage_delete, :eperm}} = PurgeWorker.run(args, opts(c))
      removed(c, parent)
      unblock(c, child)
      assert :ok = PurgeWorker.run(args, opts(c))
      removed(c, child)
    end
  end

  test "a newly shared captured derivative survives native parent fencing and retry", c do
    {_ref, parent, child, args} = graph(c, :variant)
    attach("Export", 999, "file", child.id)
    block(c, parent)
    assert {:error, {:storage_delete, :eperm}} = PurgeWorker.run(args, opts(c))
    unblock(c, parent)
    assert :ok = PurgeWorker.run(args, opts(c))
    removed(c, parent)
    assert File.exists?(path(c, child))
    assert [[child.id]] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [child.id])

    assert [[false]] ==
             rows(
               "SELECT metadata::jsonb ? 'phoenix_purge_pending' FROM active_storage_blobs WHERE id=$1",
               [child.id]
             )
  end

  defp graph(c, kind) do
    bytes = "<gpx/>"

    attrs = %{
      filename: Ecto.UUID.generate() <> ".gpx",
      byte_size: byte_size(bytes),
      checksum: Base.encode64(:crypto.hash(:md5, bytes)),
      content_type: "application/gpx+xml"
    }

    assert {:ok, ref} =
             Uploads.reserve(c.scope, attrs, %{repo: Repo, storage: c.storage, kind: :imports})

    [[id]] = rows("SELECT blob_id FROM phoenix.native_uploads WHERE reference=$1", [ref])
    parent = Storage.Blobs.find(id)
    write(c, parent, bytes)

    assert {:ok, [import]} =
             Imports.create(c.scope, [ref], repo: Repo, services: %{"local" => c.storage})

    key = Storage.generate_key()

    [[child_id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,metadata,service_name,byte_size,created_at) VALUES($1,'child','{}','local',5,now()) RETURNING id",
        [key]
      )

    child = %{id: child_id, key: key}
    write(c, child, "child")

    if kind == :variant do
      [[variant]] =
        rows(
          "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,$2) RETURNING id",
          [id, Ecto.UUID.generate()]
        )

      attach("ActiveStorage::VariantRecord", variant, "image", child_id)
    else
      attach("ActiveStorage::Blob", id, "preview_image", child_id)
    end

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               rows(
                 "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
                 [import]
               )

               PurgeWorker.enqueue!(Repo, [id])
             end)

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker' AND (args->'blob_ids'->>0)::bigint=$1 ORDER BY id DESC LIMIT 1",
        [id]
      )

    assert length(args["objects"]) == 2
    {ref, parent, child, args}
  end

  defp attach(type, id, name, blob),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES($1,$2,$3,$4,now())",
        [name, type, id, blob]
      )

  defp opts(c),
    do: [
      repo: Repo,
      services: %{"local" => c.storage},
      resolve_service: fn _ -> {:ok, c.storage} end
    ]

  defp path(c, blob), do: Storage.disk_path(c.storage.root, blob.key)

  defp write(c, blob, bytes) do
    File.mkdir_p!(Path.dirname(path(c, blob)))
    File.write!(path(c, blob), bytes)
  end

  defp block(c, blob) do
    File.rm!(path(c, blob))
    File.mkdir!(path(c, blob))
  end

  defp unblock(c, blob) do
    File.rmdir!(path(c, blob))
    write(c, blob, "retry")
  end

  defp removed(c, blob) do
    refute File.exists?(path(c, blob))
    assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
  end
end
