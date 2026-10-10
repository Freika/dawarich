defmodule Dawarich.Exports.PurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :exports, max_attempts: 26
  alias Dawarich.Storage
  alias Dawarich.Storage.NativePurge

  def enqueue!(repo, blob_ids, worker \\ __MODULE__) do
    blob_ids = NativePurge.unmarked_ids(repo, blob_ids)
    objects = NativePurge.collect(repo, blob_ids)

    if objects != [] do
      NativePurge.mark!(repo, objects)
      repo.insert!(worker.new(%{"blob_ids" => blob_ids, "objects" => objects}), prefix: "oban")
    end

    :ok
  end

  def enqueue_export!(repo, blob_ids), do: enqueue!(repo, blob_ids)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(args)

  def run(args, opts \\ []) do
    resolve_service =
      Keyword.get_lazy(opts, :resolve_service, fn ->
        services =
          Keyword.get_lazy(opts, :services, fn -> Storage.services!(System.get_env()) end)

        fn object -> {:ok, Storage.service!(services, object["service_name"])} end
      end)

    repo = Keyword.get_lazy(opts, :repo, &Dawarich.Jobs.repo/0)

    case repo.transaction(fn ->
           objects = current_objects(repo, args)

           for object <- objects do
             case resolve_service.(object) do
               {:ok, config} ->
                 case Storage.delete(config, object["key"]) do
                   :ok -> :ok
                   {:error, reason} -> repo.rollback({:storage_delete, reason})
                 end

               {:error, reason} ->
                 repo.rollback(reason)
             end
           end

           NativePurge.remove!(repo, Enum.filter(objects, &Map.has_key?(&1, "blob_id")))
           :ok
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp current_objects(repo, %{"blob_ids" => ids, "objects" => accepted}) do
    current = NativePurge.collect(repo, ids)
    protected = Enum.map(accepted, & &1["blob_id"]) -- Enum.map(current, & &1["blob_id"])

    repo.query!(
      "UPDATE active_storage_blobs SET metadata=(metadata::jsonb - 'phoenix_purge_pending')::text WHERE id=ANY($1)",
      [protected],
      log: false
    )

    missing =
      Enum.filter(accepted, fn object ->
        repo.query!("SELECT id FROM active_storage_blobs WHERE id=$1", [object["blob_id"]],
          log: false
        ).rows == []
      end)

    Enum.uniq(current ++ missing)
  end

  defp current_objects(_repo, %{"objects" => objects}), do: objects
end
