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

    with {:ok, objects} <-
           repo.transaction(fn ->
             objects = current_objects(repo, args)

             present =
               Enum.filter(objects, fn object ->
                 repo.query!(
                   "SELECT id FROM active_storage_blobs WHERE id=$1",
                   [object["blob_id"]],
                   log: false
                 ).rows != []
               end)

             NativePurge.mark!(repo, present)
             native = Enum.filter(present, &Dawarich.Uploads.DeletionDebt.retained?(repo, &1))
             NativePurge.remove!(repo, native)
             objects
           end),
         :ok <- delete_objects(objects, resolve_service),
         {:ok, :ok} <-
           repo.transaction(fn ->
             NativePurge.remove!(repo, Enum.filter(objects, &Map.has_key?(&1, "blob_id")))
             :ok
           end) do
      :ok
    end
  end

  defp delete_objects(objects, resolve_service) do
    Enum.reduce_while(objects, :ok, fn object, :ok ->
      case resolve_service.(object) do
        {:ok, config} ->
          case Storage.delete(config, object["key"]) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, {:storage_delete, reason}}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp current_objects(repo, %{"blob_ids" => ids, "objects" => accepted}) do
    identities = Map.new(accepted, &{&1["blob_id"], &1})

    current =
      NativePurge.collect(repo, Enum.uniq(ids ++ Map.keys(identities)))
      |> Enum.filter(fn object ->
        case identities[object["blob_id"]] do
          nil -> true
          identity -> identity == object
        end
      end)

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
