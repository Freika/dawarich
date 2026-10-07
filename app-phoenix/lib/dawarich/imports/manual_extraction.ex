defmodule Dawarich.Imports.ManualExtraction do
  @moduledoc false
  alias Dawarich.Imports.{UiRecords, Postprocessing.Policy, Events}
  alias Dawarich.Jobs.Ownership

  def enqueue(repo, user_id, id, action, params, context) do
    with {:ok, record} <- UiRecords.get(repo, user_id, id) do
      result =
        repo.transaction(fn ->
          unless repo.query!(
                   "SELECT i.id FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2 AND u.deleted_at IS NULL FOR UPDATE OF i FOR SHARE OF u",
                   [record.id, user_id],
                   log: false
                 ).rows == [[record.id]],
                 do: repo.rollback(:not_found)

          {:ok, record} = UiRecords.get(repo, user_id, record.id)

          command =
            if action == :extract,
              do: "enhanced_import.extract_gpx",
              else: "enhanced_import.destroy_gpx"

          standalone = Dawarich.Standalone.enabled?()

          if standalone and action == :extract and record.source not in [0, 3, 4, 13],
            do: repo.rollback(:unsupported)

          native =
            record.source in [0, 3, 4, 13] and
              (standalone or Ownership.lock(repo, "command:" <> command) == :oban)

          data = record.additional_data_extraction || %{}
          unless is_map(data), do: repo.rollback(:legacy_metadata)
          if record.status == 4, do: repo.rollback(:not_found)

          if record.additional_data_extraction_status in [1, 2] and
               not Policy.tracks?(record, context),
             do: repo.rollback(if(native, do: :native_in_flight, else: :in_flight))

          validate!(repo, record, action)
          event = Ecto.UUID.generate()
          started = DateTime.to_iso8601(context.now)

          data =
            data
            |> Map.put("started_at", started)
            |> Map.put("phoenix_extraction_event", event)
            |> Map.put("phoenix_extraction_action", to_string(action))

          data =
            if action == :extract,
              do:
                Map.put(data, "options", %{
                  "trust_source" => boolean(Map.get(params, "trust_source", true))
                }),
              else: data

          repo.query!(
            "UPDATE imports SET additional_data_extraction_status=$2,additional_data_extraction=$3 WHERE id=$1",
            [record.id, if(action == :extract, do: 1, else: 2), data],
            log: false
          )

          payload = %{
            "import_id" => record.id,
            "user_id" => user_id,
            "source" => record.source,
            "source_blob_id" => record.source_blob_id,
            "event_id" => event,
            "started_at" => started,
            "time_zone" => context.zone,
            "locale" => context.locale
          }

          kind =
            if action == :extract,
              do: "imports.extraction_requested",
              else: "imports.extraction_destroy_requested"

          children =
            action == :remove and native and
              repo.query!(
                "SELECT EXISTS(SELECT 1 FROM visits WHERE user_id=$1 AND import_id=$2) OR EXISTS(SELECT 1 FROM tracks WHERE user_id=$1 AND import_id=$2)",
                [user_id, record.id],
                log: false
              ).rows == [[true]]

          if action == :remove and (standalone or children) do
            args = Map.take(payload, ~w(import_id user_id source source_blob_id event_id))
            repo.insert!(Dawarich.Imports.ExtractionRemovalWorker.new(args), prefix: "oban")
          else
            if native and action == :extract and record.source in [0, 3, 13] do
              args =
                Map.put(payload, "lock_attempt", 1)

              Dawarich.EnhancedImport.NormalWorker.enqueue!(repo, args, event, context.now)
            else
              if native do
                args =
                  if action == :extract,
                    do: Map.put(payload, "lock_attempt", 1),
                    else: payload

                repo.query!(
                  "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,$2,1,$3,$4,$5,now())",
                  [
                    Ecto.UUID.dump!(event),
                    command,
                    args,
                    %{"producer" => "Phoenix manual extraction"},
                    user_id
                  ],
                  log: false
                )
              else
                Dawarich.RailsCommands.insert!(repo, kind, payload)
              end
            end
          end

          :queued
        end)

      if match?({:ok, _}, result), do: Events.broadcast(user_id)
      result
    end
  end

  defp validate!(repo, record, :extract) do
    unless Policy.extracts?(%{record | additional_data_extraction_status: 0}),
      do: repo.rollback(:unsupported)
  end

  defp validate!(repo, record, :remove) do
    unless record.source in [0, 3, 4, 13] and record.additional_data_extraction_status != 0,
      do: repo.rollback(:unsupported)
  end

  defp boolean(value) when value in [nil, ""], do: nil
  defp boolean(value), do: value not in [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]
end
