defmodule Dawarich.Imports.Postprocessing.Commands do
  @moduledoc false
  alias Dawarich.{RailsCommands, TimeZoneName}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Imports.Postprocessing.Snapshot

  def reverse!(repo, import, context, step, extra \\ %{}) do
    native = Dawarich.Imports.Postprocessing.Native

    types = %{
      "schedule_stats" => ["stats.calculate_month", "achievements.check"],
      "schedule_visit_suggesting" => ["visits.suggest"],
      "extract" => ["enhanced_import.extract_gpx"]
    }

    if Map.has_key?(types, step) and Enum.all?(types[step], &native.selected?(repo, &1)) do
      native.run!(repo, import, context, step, extra)
    else
      reverse_source!(repo, import, context, step, extra)
    end
  end

  defp reverse_source!(repo, import, context, step, extra) do
    RailsCommands.insert!(
      repo,
      "imports.postprocessing_step",
      Map.merge(
        %{
          "user_id" => import.user_id,
          "import_id" => import.id,
          "locale" => context.locale,
          "time_zone" => context.zone,
          "step" => step
        },
        extra
      )
    )
  end

  def produce!(repo, import, context, type, payload, aggregate) do
    if Dawarich.Standalone.enabled?() do
      {:ok, worker} = Dawarich.Jobs.Registry.command(type)

      Dawarich.Imports.Postprocessing.Native.publish!(
        repo,
        worker,
        payload,
        Dawarich.Imports.Postprocessing.Native.identity(repo, import.id),
        Snapshot.clock(context)
      )
    else
      case Ownership.lock(repo, "command:" <> type) do
        :oban ->
          repo.query!(
            """
            INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at)
            VALUES(gen_random_uuid(),$1,1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING
            """,
            [
              type,
              payload,
              %{"producer" => "Phoenix Imports Postprocessing"},
              aggregate,
              if(type == "imports.update_points_count", do: "points-count:#{import.id}"),
              Snapshot.clock(context)
            ],
            log: false
          )

        :sidekiq ->
          reverse!(repo, import, context, "command", %{
            "command_type" => type,
            "command_payload" => payload,
            "aggregate_id" => aggregate
          })
      end
    end

    :ok
  end

  def track_payload(import, context, summary) do
    %{
      "user_id" => import.user_id,
      "start_at" => iso(summary.first),
      "end_at" => iso(summary.last),
      "time_zone" => TimeZoneName.to_iana(context.zone),
      "mode" => "bulk",
      "untracked_only" => true,
      "import_id" => import.id,
      "low_priority" => false
    }
  end

  def iso(stamp), do: stamp |> DateTime.from_unix!() |> DateTime.to_iso8601()
end
