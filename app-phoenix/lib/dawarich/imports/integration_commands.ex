defmodule Dawarich.Imports.IntegrationCommands do
  @moduledoc false
  alias Dawarich.{Jobs.Ownership, TimeZoneName, UserSettings}

  @jobs %{
    "start_immich_import" => "imports.immich_geodata",
    "start_photoprism_import" => "imports.photoprism_geodata"
  }

  def enqueue(repo, user_id, job) when is_binary(job) do
    case Map.fetch(@jobs, job) do
      {:ok, kind} -> enqueue_kind(repo, user_id, kind)
      :error -> {:error, :unknown_job}
    end
  end

  def enqueue(_repo, _user_id, _job), do: {:error, :unknown_job}

  defp enqueue_kind(repo, user_id, kind) do
    repo.transaction(
      fn ->
        if Ownership.lock(repo, "command:" <> kind) != :oban,
          do: repo.rollback(:not_owned)

        settings =
          case repo.query!(
                 "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR SHARE",
                 [user_id],
                 log: false
               ).rows do
            [[%{} = settings]] -> settings
            _ -> repo.rollback(:not_found)
          end

        zone = UserSettings.safe(settings)["timezone"] |> TimeZoneName.to_iana()
        Dawarich.Imports.ZonePeriod.load!(zone)
        event = Ecto.UUID.generate()
        payload = %{"user_id" => user_id, "time_zone" => zone}

        repo.query!(
          "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6,now())",
          [
            Ecto.UUID.dump!(event),
            kind,
            payload,
            %{"producer" => "Phoenix integration trigger"},
            user_id,
            "integration-trigger:" <> event
          ],
          log: false
        )

        :queued
      end,
      mode: :savepoint
    )
  rescue
    _ -> {:error, :enqueue_failed}
  end
end
