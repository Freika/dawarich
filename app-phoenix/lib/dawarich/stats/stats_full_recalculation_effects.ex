defmodule Dawarich.Stats.StatsFullRecalculationEffects do
  @moduledoc false
  alias Dawarich.{Jobs.Ownership, RailsCommands, Standalone}

  alias Dawarich.Jobs.Processed
  alias Dawarich.Stats.EffectIdentity

  def call(repo, payload) do
    receipt =
      EffectIdentity.id(payload["source_job_id"], "stats.full_recalculation:schedule", payload)

    :ok =
      Processed.once(repo, receipt, "stats.full_recalculation:schedule", fn ->
        if Standalone.enabled?() or
             Ownership.lock(repo, "command:stats.full_recalculation") == :oban do
          native(repo, payload)
        else
          RailsCommands.insert!(repo, "stats.full_recalculation", payload)
        end

        :ok
      end)

    :ok
  end

  defp native(repo, payload) do
    repo.query!(
      "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,'stats.full_recalculation',1,$2,$3,$4,$5) ON CONFLICT DO NOTHING",
      [
        Ecto.UUID.dump!(
          EffectIdentity.id(payload["source_job_id"], "stats.full_recalculation", payload)
        ),
        Map.delete(payload, "run_at"),
        %{"producer" => "Phoenix stats"},
        payload["user_id"],
        DateTime.from_unix!(round(payload["run_at"] * 1_000_000), :microsecond)
      ],
      log: false
    )
  end
end
