defmodule Dawarich.Imports.Teslamate.ScheduleWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  @key "cron:teslamate_sync_job"

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(Dawarich.Jobs.repo())

  def run(repo) do
    Dawarich.Jobs.Ownership.with_owner(repo, @key, :oban, fn ->
      users =
        repo.query!(
          "SELECT id FROM users WHERE deleted_at IS NULL AND settings->>'teslamate_url' <> '' ORDER BY id",
          [],
          log: false
        ).rows

      for [id] <- users do
        payload = %{"user_id" => id}

        repo.query!(
          "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,metadata,scheduled_at) VALUES($1,'imports.teslamate_sync',1,$2,$3,$4,now())",
          [
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            payload,
            id,
            %{"producer" => "TeslaMate sync scheduler"}
          ],
          log: false
        )
      end
    end)

    :ok
  end
end
