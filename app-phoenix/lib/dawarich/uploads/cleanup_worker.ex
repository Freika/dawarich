defmodule Dawarich.Uploads.CleanupWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 26,
    unique: [period: :infinity, keys: [:reference], states: [:available, :scheduled, :retryable]]

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
           "SELECT user_id FROM phoenix.native_uploads WHERE reference=$1 AND state IN ('cancelled','expired','purged')",
           [ref],
           log: false
         ).rows do
      [[id]] -> Records.read(repo, ref, id)
      _ -> nil
    end
  end

  defp purge(repo, ref, opts) do
    with {:ok, row} when not is_nil(row) <- fence(repo, ref),
         services <-
           Keyword.get_lazy(opts, :services, &Dawarich.Imports.StorageContext.services/0),
         {:ok, service} <-
           Storage.ImportServices.resolve(services, %{
             service_name: row.service_name,
             key: row.object_key
           }),
         :ok <- Storage.delete(service, row.object_key) do
      repo.transaction(fn ->
        locked = Records.read(repo, ref, row.user_id, true)
        Records.finish!(repo, locked, "purged")
        next = if service.service == "s3", do: NaiveDateTime.add(NaiveDateTime.utc_now(), 300)

        repo.query!(
          "UPDATE phoenix.native_uploads SET cleanup_at=$2 WHERE reference=$1",
          [ref, next],
          log: false
        )

        if next,
          do:
            repo.insert!(
              Dawarich.Uploads.SweepWorker.new(%{},
                scheduled_at: DateTime.from_naive!(next, "Etc/UTC")
              ),
              prefix: "oban"
            )

        :ok
      end)
      |> case do
        {:ok, :ok} -> :ok
        error -> error
      end
    else
      {:ok, nil} -> :ok
      error -> error
    end
  end

  defp fence(repo, ref) do
    repo.transaction(fn ->
      row = snapshot(repo, ref)
      locked = row && Records.read(repo, ref, row.user_id, true)

      if locked && locked.state in ["cancelled", "expired", "purged"] do
        blobs =
          repo.query!(
            "SELECT key,service_name,metadata FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
            [locked.blob_id],
            log: false
          ).rows

        locked = identity(repo, locked, blobs)

        cond do
          Records.attached?(repo, locked.blob_id) ->
            nil

          is_nil(locked.object_key) or is_nil(locked.service_name) ->
            repo.rollback(:missing_cleanup_identity)

          blobs == [] ->
            locked

          Enum.any?(blobs, fn [key, service, metadata] ->
            key != locked.object_key or service != locked.service_name or
                not Storage.NativePurge.pending?(metadata)
          end) ->
            repo.rollback(:not_tombstoned)

          true ->
            Storage.NativePurge.remove!(repo, [%{"blob_id" => locked.blob_id}])
            locked
        end
      end
    end)
  end

  defp identity(repo, %{object_key: nil} = row, [[key, service, metadata]]) do
    if Storage.NativePurge.pending?(metadata) and
         Storage.UploadReceipts.owned?(repo, row.blob_id, row.user_id) do
      repo.query!(
        "UPDATE phoenix.native_uploads SET object_key=$2,service_name=$3 WHERE reference=$1",
        [row.reference, key, service], log: false)

      %{row | object_key: key, service_name: service}
    else
      row
    end
  end

  defp identity(_repo, row, _blobs), do: row
end
