defmodule Dawarich.Posters.PurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :posters, max_attempts: 26
  alias Dawarich.{RailsRoot, Storage}
  alias Dawarich.Jobs.Processed
  alias Dawarich.Posters.Command

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args, opts \\ []) do
    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      services =
        Keyword.get_lazy(opts, :services, fn ->
          Storage.services!(System.get_env(), RailsRoot.root())
        end)

      result =
        Enum.reduce_while(args["blob_ids"], :ok, fn id, :ok ->
          case purge(repo, args["poster_id"], id, services) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)

      if result == :ok, do: Processed.mark!(repo, args["event_id"], "posters.purge")
      result
    end
  end

  defp purge(repo, poster, id, services) do
    {:ok, blob} =
      repo.transaction(fn ->
        case repo.query!(
               "SELECT key,service_name FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
               [id],
               log: false
             ).rows do
          [[key, service]] ->
            [[referenced]] =
              repo.query!(
                "SELECT EXISTS(SELECT 1 FROM posters WHERE id=$1) OR EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$2)",
                [poster, id],
                log: false
              ).rows

            if referenced do
              nil
            else
              children =
                repo.query!(
                  "DELETE FROM active_storage_attachments WHERE record_type='ActiveStorage::VariantRecord' AND record_id IN (SELECT id FROM active_storage_variant_records WHERE blob_id=$1) RETURNING blob_id",
                  [id],
                  log: false
                ).rows
                |> List.flatten()
                |> Enum.uniq()

              if children != [], do: Command.purge(repo, :oban, %{"blob_ids" => children})

              repo.query!("DELETE FROM active_storage_variant_records WHERE blob_id=$1", [id],
                log: false
              )

              repo.query!("DELETE FROM active_storage_blobs WHERE id=$1", [id], log: false)
              {key, service}
            end

          [] ->
            nil
        end
      end)

    case blob do
      nil ->
        :ok

      {key, service} ->
        case Storage.delete(Storage.service!(services, service), key) do
          :ok -> :ok
          {:error, reason} -> {:error, {:storage_delete, reason}}
        end
    end
  end
end
