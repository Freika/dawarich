defmodule Dawarich.Points.ApiAnomaly do
  @moduledoc false
  alias Dawarich.Imports.Api
  alias Dawarich.{I18n, RailsCache, Redis}
  alias Dawarich.RailsCache.Wire
  alias Dawarich.Jobs.Ownership

  def reapply(repo, user, _params, ctx) do
    with :ok <- Api.guard(user, ctx) do
      key = "anomaly_backfill_pending:#{user.id}"

      case RailsCache.get(key) do
        {:ok, value} when value not in [false, nil] ->
          error(409, "anomaly_re_evaluation_already_in_progress")

        _ ->
          bytes = Wire.encode_boolean(true, expires_at: System.os_time(:second) + 1800)
          {:ok, _} = Redis.cache_command(["SET", key, bytes, "EX", "1800"])
          enqueue(repo, user)

          {:ok, 202,
           %{
             "message" =>
               I18n.en!(
                 "controllers.api.v1.points.re_evaluation_queued_existing_anomaly_flags_will_be_cleared_and"
               )
           }}
      end
    end
  end

  defp enqueue(repo, user) do
    {:ok, _} =
      repo.transaction(fn ->
        owner = Ownership.lock(repo, "command:points.anomaly_backfill")

        payload = %{
          "user_id" => user.id,
          "reset" => true,
          "notify" => true,
          "rebuild" => "async",
          "source_job_id" => Ecto.UUID.generate(),
          "ambient_zone" => Dawarich.UserTimeZone.name(user.settings, repo),
          "progress" => %{}
        }

        if owner == :oban do
          repo.query!(
            "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),'points.anomaly_backfill',1,$1,$2,$3,now())",
            [payload, %{"producer" => "Phoenix Point Anomaly API"}, user.id]
          )
        else
          Dawarich.RailsCommands.insert!(repo, "points.anomaly_backfill", payload)
        end
      end)
  end

  defp error(status, key), do: Api.error(status, "controllers.api.v1.points." <> key)
end
