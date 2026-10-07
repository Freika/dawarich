defmodule Dawarich.Tracks.WebRecalculation do
  @moduledoc false
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Transportation.{RecalculationFence, RecalculationStatus}

  def create(repo, user, ctx) do
    repo.transaction(fn ->
      repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [user.id])

      if RecalculationStatus.in_progress?(user.id) do
        :running
      else
        if Ownership.lock(repo, "command:transportation.user_reclassify") != :oban,
          do: repo.rollback(:rails)

        event = Ecto.UUID.generate()

        if RecalculationFence.claim(repo, user.id, event) do
          repo.query!(
            "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,'transportation.user_reclassify',1,$2,$3,$4,$5)",
            [
              Ecto.UUID.dump!(event),
              %{"user_id" => user.id},
              %{"producer" => "Phoenix TrackRecalculation"},
              user.id,
              ctx.now
            ]
          )

          :started
        else
          :running
        end
      end
    end)
  end
end
