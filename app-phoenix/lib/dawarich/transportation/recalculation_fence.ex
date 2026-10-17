defmodule Dawarich.Transportation.RecalculationFence do
  @moduledoc false

  def waiting(repo, user) do
    case repo.query!(
           "SELECT job.scheduled_at FROM phoenix.transportation_recalculations fence LEFT JOIN public.job_outbox job ON job.event_id=fence.event_id WHERE fence.user_id=$1 AND fence.remaining IS NULL",
           [user],
           log: false
         ).rows do
      [[at]] ->
        %{
          "status" => "processing",
          "total_tracks" => 0,
          "processed_tracks" => 0,
          "started_at" => at && DateTime.to_iso8601(at)
        }

      [] ->
        nil
    end
  end

  def admit_progress?(repo, user, event) do
    [[admitted]] =
      repo.query!(
        "SELECT NOT EXISTS(SELECT 1 FROM phoenix.transportation_recalculations WHERE user_id=$1) OR EXISTS(SELECT 1 FROM phoenix.transportation_recalculations fence JOIN public.job_outbox child ON child.metadata->>'parent_event_id'=fence.event_id::text WHERE fence.user_id=$1 AND fence.remaining>0 AND child.event_id=$2)",
        [user, Ecto.UUID.dump!(event)],
        log: false
      ).rows

    admitted
  end

  def claim(repo, user, event) do
    repo.query!(
      "INSERT INTO phoenix.transportation_recalculations(user_id,event_id) VALUES($1,$2) ON CONFLICT(user_id) DO NOTHING RETURNING user_id",
      [user, Ecto.UUID.dump!(event)],
      log: false
    ).num_rows == 1
  end

  def start(repo, user, event, total) do
    if total == 0 do
      release(repo, user, event)
    else
      repo.query!(
        "UPDATE phoenix.transportation_recalculations SET remaining=$3 WHERE user_id=$1 AND event_id=$2",
        [user, Ecto.UUID.dump!(event), total],
        log: false
      )
    end

    :ok
  end

  def progress(repo, user, event) do
    repo.query!(
      "UPDATE phoenix.transportation_recalculations AS fence SET remaining=remaining-1 FROM public.job_outbox AS child WHERE fence.user_id=$1 AND child.event_id=$2 AND child.metadata->>'parent_event_id'=fence.event_id::text",
      [user, Ecto.UUID.dump!(event)],
      log: false
    )

    repo.query!(
      "DELETE FROM phoenix.transportation_recalculations WHERE user_id=$1 AND remaining<=0",
      [user],
      log: false
    )

    :ok
  end

  def release(repo, user, event) do
    repo.query!(
      "DELETE FROM phoenix.transportation_recalculations WHERE user_id=$1 AND event_id=$2",
      [user, Ecto.UUID.dump!(event)],
      log: false
    )

    :ok
  end
end
