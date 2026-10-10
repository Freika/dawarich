defmodule Dawarich.Uploads.Reservations do
  @moduledoc false
  alias Dawarich.Uploads.{Policy, Records}
  alias Dawarich.Storage.Blobs
  alias Dawarich.{Entitlements, Repo}

  def reserve(scope, entry, policy) do
    repo = Map.get(policy, :repo, Repo)
    kind = Map.get(policy, :kind, :imports)
    limits = Policy.limits(policy)

    with {:ok, _} <- Dawarich.Accounts.NativeAccess.admit(scope, repo),
         true <- kind in [:imports, :account] and Policy.valid?(entry, kind, limits) do
      repo.transaction(fn ->
        current = Records.actor!(repo, scope)
        budget!(repo, current.user, entry, kind, limits)
        storage = Map.get_lazy(policy, :storage, &Dawarich.Imports.StorageContext.storage/0)
        now = NaiveDateTime.utc_now()

        attrs = %{
          "filename" => entry.filename,
          "byte_size" => entry.byte_size,
          "checksum" => entry.checksum,
          "content_type" => entry.content_type
        }

        {:ok, blob} =
          Blobs.create_before_direct_upload(storage, attrs, now,
            user_id: current.user.id,
            repo: repo
          )

        ref = Ecto.UUID.generate()

        repo.query!(
          "INSERT INTO phoenix.native_uploads(reference,user_id,blob_id,kind,original_filename,original_size,client_wrapped,expires_at,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
          [
            ref,
            current.user.id,
            blob.id,
            Atom.to_string(kind),
            Map.get(entry, :original_filename, entry.filename),
            Map.get(entry, :original_size, entry.byte_size),
            Map.get(entry, :client_wrapped, false),
            NaiveDateTime.add(now, limits.ttl),
            now
          ], log: false)

        repo.insert!(
          Dawarich.Uploads.SweepWorker.new(%{},
            scheduled_at: DateTime.add(DateTime.utc_now(), limits.ttl)
          ), prefix: "oban")

        ref
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_input}
    end
  end

  defp budget!(repo, user, entry, kind, limits) do
    [[count, bytes]] =
      repo.query!(
        "SELECT count(*),coalesce(sum(b.byte_size),0)::bigint FROM phoenix.native_uploads u JOIN active_storage_blobs b ON b.id=u.blob_id WHERE u.user_id=$1 AND u.kind=$2 AND u.state='pending' AND u.expires_at>timezone('UTC',now())",
        [user.id, Atom.to_string(kind)], log: false).rows

    max_entries = if kind == :account, do: 1, else: limits.max_entries

    if count >= max_entries or bytes + entry.byte_size > limits.aggregate_bytes,
      do: repo.rollback(:limit)

    unless Entitlements.future?(user.active_until, DateTime.utc_now()),
      do: repo.rollback(:inactive)

    if kind == :imports and not Dawarich.ReleaseMigration.self_hosted?() and
         (user.points_count || 0) >= 10_000_000, do: repo.rollback(:points_limit)

    if user.status == 2 and user.subscription_source in [nil, 0] do
      if entry.byte_size > 11 * 1024 * 1024 or
           Map.get(entry, :original_size, entry.byte_size) > 11 * 1024 * 1024,
         do: repo.rollback(:file_too_large)

      if kind == :imports do
        [[imports]] =
          repo.query!("SELECT count(*) FROM imports WHERE user_id=$1 AND demo=false", [user.id],
            log: false
          ).rows

        if imports + count >= 5, do: repo.rollback(:import_limit)
      end
    end
  end
end
