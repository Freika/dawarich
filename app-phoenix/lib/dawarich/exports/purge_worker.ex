defmodule Dawarich.Exports.PurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :exports, max_attempts: 26
  alias Dawarich.Storage

  def enqueue!(repo, blob_ids) do
    objects = blob_ids |> Enum.flat_map(&revoke!(repo, &1)) |> Enum.uniq()

    if objects != [] do
      repo.insert!(new(%{"objects" => objects}), prefix: "oban")
    end

    :ok
  end

  defp revoke!(repo, id) do
    case repo.query!(
           "SELECT key,service_name FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
           [id],
           log: false
         ).rows do
      [[key, service]] ->
        [[shared]] =
          repo.query!(
            "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1)",
            [id],
            log: false
          ).rows

        if shared do
          []
        else
          children =
            repo.query!(
              "DELETE FROM active_storage_attachments WHERE record_type='ActiveStorage::VariantRecord' AND record_id IN (SELECT id FROM active_storage_variant_records WHERE blob_id=$1) RETURNING blob_id",
              [id],
              log: false
            ).rows
            |> List.flatten()
            |> Enum.uniq()
            |> Enum.sort()

          repo.query!("DELETE FROM active_storage_variant_records WHERE blob_id=$1", [id],
            log: false
          )

          repo.query!("DELETE FROM active_storage_blobs WHERE id=$1", [id], log: false)

          [
            %{"key" => key, "service_name" => service}
            | Enum.flat_map(children, &revoke!(repo, &1))
          ]
        end

      [] ->
        []
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(args)

  def run(%{"objects" => objects}, opts \\ []) do
    services = Keyword.get_lazy(opts, :services, fn -> Storage.services!(System.get_env()) end)

    Enum.reduce_while(objects, :ok, fn object, :ok ->
      case Storage.delete(Storage.service!(services, object["service_name"]), object["key"]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:storage_delete, reason}}}
      end
    end)
  end
end
