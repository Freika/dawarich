defmodule Dawarich.Imports.PreparedDownloadPurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :imports, max_attempts: 26
  alias Dawarich.Imports.StorageContext
  alias Dawarich.Storage

  def enqueue!(repo, ids) do
    objects = ids |> Enum.sort() |> Enum.flat_map(&revoke!(repo, &1))
    if objects != [], do: repo.insert!(new(%{"objects" => objects}), prefix: "oban")
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
              "DELETE FROM active_storage_attachments WHERE record_type='ActiveStorage::VariantRecord' AND record_id IN(SELECT id FROM active_storage_variant_records WHERE blob_id=$1) RETURNING blob_id",
              [id],
              log: false
            ).rows
            |> List.flatten()
            |> Enum.uniq()

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
  def perform(%Oban.Job{args: %{"objects" => objects}}) do
    Enum.reduce_while(objects, :ok, fn object, :ok ->
      with {:ok, config} <-
             Storage.ImportServices.resolve(StorageContext.services(), %{
               key: object["key"],
               service_name: object["service_name"]
             }),
           :ok <- Storage.delete(config, object["key"]) do
        {:cont, :ok}
      else
        {:legacy, reason} -> {:halt, {:error, reason}}
        {:error, reason} -> {:halt, {:error, {:storage_delete, reason}}}
      end
    end)
  end
end
