defmodule Dawarich.UserData.ImportCommands do
  @moduledoc false
  alias Dawarich.Imports.ImportState
  @command "users.import_data"

  def args(
        1,
        %{"import_id" => id, "user_id" => user, "time_zone" => zone, "locale" => locale} = payload
      )
      when is_integer(id) and id > 0 and is_integer(user) and user > 0 and
             is_binary(zone) and byte_size(zone) > 0 and is_binary(locale) and
             byte_size(locale) > 0 and map_size(payload) == 4 do
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    {:ok, payload}
  rescue
    _ -> {:error, "invalid_payload"}
  end

  def args(1, _), do: {:error, "invalid_payload"}
  def args(_, _), do: {:error, "unsupported_version"}

  def enqueue(repo, import, context) do
    payload = %{
      "import_id" => import.id,
      "user_id" => import.user_id,
      "time_zone" => context.zone,
      "locale" => context.locale
    }

    if Dawarich.Jobs.Ownership.lock(repo, "command:" <> @command) == :oban do
      repo.query!(
        "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES(gen_random_uuid(),$1,1,$2,$3,$4,$5,now())",
        [
          @command,
          payload,
          %{"producer" => "Phoenix UserDataImport"},
          import.id,
          "user-data-import:#{import.id}"
        ],
        log: false
      )
    else
      Dawarich.RailsCommands.insert!(repo, @command, payload)
    end

    :ok
  end

  def discover(lease, context) do
    ImportState.effect!(lease, fn ->
      lease.repo.query!(
        "UPDATE imports SET source=8,additional_data_extraction_status=5 WHERE id=$1",
        [lease.import.id],
        log: false
      )

      enqueue(lease.repo, lease.import, context)
      Dawarich.Jobs.Processed.mark!(lease.repo, lease.event_id, "imports.process_normal")

      lease.repo.query!(
        "DELETE FROM phoenix.import_runs WHERE import_id=$1 AND event_id=$2 AND token=$3",
        [lease.import.id, lease.event, lease.token],
        log: false
      )
    end)

    :restore_handoff
  end
end
