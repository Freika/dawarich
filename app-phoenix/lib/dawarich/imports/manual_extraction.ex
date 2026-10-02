defmodule Dawarich.Imports.ManualExtraction do
  @moduledoc false
  alias Dawarich.Imports.{UiRecords, Postprocessing.Policy, Events}

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
          data = record.additional_data_extraction || %{}
          unless is_map(data), do: repo.rollback(:legacy_metadata)
          if record.status == 4, do: repo.rollback(:not_found)

          if record.additional_data_extraction_status in [1, 2] and
               not Policy.tracks?(record, context),
             do: repo.rollback(:in_flight)

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

          Dawarich.RailsCommands.insert!(repo, kind, payload)
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
