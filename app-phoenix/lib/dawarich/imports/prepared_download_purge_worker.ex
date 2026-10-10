defmodule Dawarich.Imports.PreparedDownloadPurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :imports, max_attempts: 26
  alias Dawarich.Imports.StorageContext
  alias Dawarich.Storage.{ImportServices, NativePurge}

  def enqueue!(repo, ids) do
    Dawarich.Exports.PurgeWorker.enqueue!(repo, ids, __MODULE__)
    objects = NativePurge.collect(repo, ids)

    repo.query!(
      "DELETE FROM phoenix.upload_receipts WHERE blob_id=ANY($1)",
      [Enum.map(objects, & &1["blob_id"])],
      log: false
    )

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    services = StorageContext.services()

    Dawarich.Exports.PurgeWorker.run(args,
      resolve_service: fn object ->
        case ImportServices.resolve(services, %{
               key: object["key"],
               service_name: object["service_name"]
             }) do
          {:ok, config} -> {:ok, config}
          {:legacy, reason} -> {:error, reason}
        end
      end
    )
  end
end
