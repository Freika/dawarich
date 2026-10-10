defmodule Dawarich.Uploads.CleanupWorker do
  @moduledoc false
  use Oban.Worker, queue: :imports, max_attempts: 26
  alias Dawarich.Uploads.Records
  alias Dawarich.Storage
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(args)

  def run(%{"reference" => ref}, opts \\ []) do
    repo = Keyword.get_lazy(opts, :repo, &Dawarich.Jobs.repo/0)

    case snapshot(repo, ref) do
      nil ->
        :ok

      %{target_until: until} when not is_nil(until) ->
        seconds = NaiveDateTime.diff(until, NaiveDateTime.utc_now())
        if seconds >= 0, do: {:snooze, seconds + 1}, else: purge(repo, ref, opts)

      _ ->
        purge(repo, ref, opts)
    end
  end

  defp snapshot(repo, ref) do
    case repo.query!(
           "SELECT user_id FROM phoenix.native_uploads WHERE reference=$1 AND state IN ('cancelled','expired')",
           [ref], log: false).rows do
      [[id]] -> Records.read(repo, ref, id)
      _ -> nil
    end
  end

  defp purge(repo, ref, opts) do
    row = snapshot(repo, ref)

    if row && not Records.attached?(repo, row.blob_id) do
      case Storage.Blobs.find(row.blob_id, repo) do
        nil -> purge_marked(repo, row, opts)
        _ -> {:error, :not_tombstoned}
      end
    else
      :ok
    end
  end

  defp purge_marked(repo, row, opts) do
    objects =
      repo.query!(
        "SELECT key,service_name FROM active_storage_blobs WHERE id=$1 AND (metadata::jsonb->>'phoenix_purge_pending')='true'",
        [row.blob_id], log: false).rows

    services = Keyword.get_lazy(opts, :services, &Dawarich.Imports.StorageContext.services/0)

    result =
      for [key, name] <- objects do
        {:ok, service} = Storage.ImportServices.resolve(services, %{service_name: name, key: key})
        Storage.delete(service, key)
      end

    if Enum.all?(result, &(&1 == :ok)) do
      case repo.transaction(fn ->
             locked = Records.read(repo, row.reference, row.user_id, true)

             if locked && locked.state in ["cancelled", "expired"] &&
                  not Records.attached?(repo, locked.blob_id) do
               Dawarich.Storage.NativePurge.remove!(repo, [%{"blob_id" => locked.blob_id}])
               Records.finish!(repo, locked, "purged")
             end

             :ok
           end) do
        {:ok, :ok} -> :ok
        error -> error
      end
    else
      {:error, :storage_delete}
    end
  end
end
