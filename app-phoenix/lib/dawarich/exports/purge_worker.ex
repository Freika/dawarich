defmodule Dawarich.Exports.PurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :exports, max_attempts: 26
  alias Dawarich.Storage
  alias Dawarich.Storage.NativePurge

  def enqueue!(repo, blob_ids) do
    blob_ids = NativePurge.unmarked_ids(repo, blob_ids)
    objects = NativePurge.collect(repo, blob_ids)

    if objects != [] do
      NativePurge.mark!(repo, objects)
      repo.insert!(new(%{"blob_ids" => blob_ids, "objects" => objects}), prefix: "oban")
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(args)

  def run(args, opts \\ []) do
    services = Keyword.get_lazy(opts, :services, fn -> Storage.services!(System.get_env()) end)
    repo = Keyword.get_lazy(opts, :repo, &Dawarich.Jobs.repo/0)

    case repo.transaction(fn ->
           objects = current_objects(repo, args)

           for object <- objects do
             case Storage.delete(
                    Storage.service!(services, object["service_name"]),
                    object["key"]
                  ) do
               :ok -> :ok
               {:error, reason} -> repo.rollback({:storage_delete, reason})
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
