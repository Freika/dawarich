defmodule Dawarich.Imports.DownloadProducer do
  @moduledoc false
  alias Dawarich.Jobs.Ownership

  def enqueue(repo, user_id, import_id, source_blob_id, now \\ DateTime.utc_now()) do
    repo.transaction(fn ->
      owner = Ownership.lock(repo, "command:imports.prepare_download")

      case repo.query!(
             "SELECT i.id FROM public.imports i JOIN public.users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2 AND i.status<>4 AND u.deleted_at IS NULL FOR UPDATE OF i",
             [import_id, user_id],
             log: false
           ).rows do
        [[^import_id]] -> :ok
        _ -> repo.rollback(:not_found)
      end

      if repo.query!(
           "SELECT 1 FROM public.active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='file' AND blob_id=$2 FOR SHARE",
           [import_id, source_blob_id],
           log: false
         ).rows == [],
         do: repo.rollback(:not_found)

      event = Ecto.UUID.generate()

      accepted =
        repo.query!(
          "INSERT INTO phoenix.import_download_requests(import_id,source_blob_id,requested_at,event_id) VALUES($1,$2,$3,$4) ON CONFLICT(import_id,source_blob_id) DO UPDATE SET requested_at=EXCLUDED.requested_at,event_id=EXCLUDED.event_id WHERE import_download_requests.requested_at<=EXCLUDED.requested_at-interval '60 seconds' RETURNING event_id",
          [import_id, source_blob_id, now, Ecto.UUID.dump!(event)],
          log: false
        ).rows

      if accepted == [] do
        :cached
      else
        payload = %{
          "import_id" => import_id,
          "user_id" => user_id,
          "source_blob_id" => source_blob_id
        }

        if owner == :oban do
          repo.query!(
            "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,'imports.prepare_download',1,$2,$3,$4,$5,$6)",
            [
              Ecto.UUID.dump!(event),
              payload,
              %{"producer" => "Phoenix ImportsDownload"},
              import_id,
              "prepare-download:#{event}",
              now
            ],
            log: false
          )
        else
          Dawarich.RailsCommands.insert!(repo, "imports.prepare_download", payload)
        end

        :queued
      end
    end)
  end
end
