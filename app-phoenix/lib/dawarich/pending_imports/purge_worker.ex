defmodule Dawarich.PendingImports.PurgeWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :maintenance,
    priority: 3,
    max_attempts: 26,
    unique: [
      keys: [:pending_import_id, :blob_id, :attachment_id],
      period: :infinity,
      states: :incomplete
    ]

  alias Dawarich.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args, opts \\ []) do
    services =
      Keyword.get_lazy(opts, :services, fn ->
        %{services: Dawarich.Imports.StorageContext.services()}
      end)

    case repo.transaction(fn -> purge(repo, args, services) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp purge(repo, args, services) do
    id = args["pending_import_id"]
    attachment = args["attachment_id"]
    blob = args["blob_id"]
    now = NaiveDateTime.from_iso8601!(args["now"])

    eligible =
      repo.query!(
        "SELECT id FROM pending_imports WHERE id=$1 AND ((claimed_at IS NULL AND expires_at <= $2) OR claimed_at < $2 - interval '7 days') FOR UPDATE",
        [id, now],
        log: false
      ).rows

    if eligible == [[id]] do
      case repo.query!(
             "SELECT key,service_name FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
             [blob],
             log: false
           ).rows do
        [[key, service]] ->
          identity =
            repo.query!(
              "SELECT id FROM active_storage_attachments WHERE id=$1 AND blob_id=$2 AND record_type='PendingImport' AND record_id=$3 AND name='file' FOR UPDATE",
              [attachment, blob, id],
              log: false
            ).rows

          if identity == [[attachment]],
            do: delete(repo, id, attachment, blob, key, service, services),
            else: :ok

        [] ->
          :ok
      end
    else
      :ok
    end
  end

  defp delete(repo, id, attachment, blob, key, service, services) do
    [[shared]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1 AND id<>$2)",
        [blob, attachment],
        log: false
      ).rows

    result = if shared, do: :ok, else: Storage.delete(Storage.service!(services, service), key)

    case result do
      :ok -> finalize(repo, id, attachment, blob, shared)
      {:error, reason} -> {:error, {:storage_delete, reason}}
    end
  end

  def finalize(repo, id, attachment, blob, shared) do
    repo.query!("DELETE FROM active_storage_attachments WHERE id=$1", [attachment], log: false)

    unless shared do
      repo.query!("DELETE FROM active_storage_variant_records WHERE blob_id=$1", [blob],
        log: false
      )

      repo.query!("DELETE FROM active_storage_blobs WHERE id=$1", [blob], log: false)
    end

    repo.query!("DELETE FROM pending_imports WHERE id=$1", [id], log: false)
    :ok
  end

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)
end
