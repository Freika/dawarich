defmodule Dawarich.Imports.Postprocessing.Native do
  @moduledoc false
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Imports.Postprocessing.Snapshot

  def selected?(repo, type),
    do: Dawarich.Standalone.enabled?() or Ownership.lock(repo, "command:" <> type) == :oban

  def run!(repo, import, context, "schedule_stats", extra) do
    for [year, month] <- extra["months"] do
      publish!(
        repo,
        Dawarich.Stats.CalculateMonthWorker,
        %{
          "user_id" => import.user_id,
          "year" => year,
          "month" => month,
          "notify_on_failure" => true
        },
        identity(repo, import.id),
        Snapshot.clock(context)
      )
    end

    Dawarich.Imports.ImportsDestroyAchievementsEffects.enqueue!(
      repo,
      import.user_id,
      extra["oldest_timestamp"],
      identity(repo, import.id),
      Snapshot.clock(context)
    )

    :ok
  end

  def run!(repo, import, context, "schedule_visit_suggesting", extra) do
    [[settings, plan]] =
      repo.query!(
        "SELECT settings,plan FROM users WHERE id=$1 AND deleted_at IS NULL",
        [import.user_id],
        log: false
      ).rows

    if Dawarich.Visits.Settings.policy(settings).suggestions_enabled do
      {:ok, start, _} = DateTime.from_iso8601(extra["start_at"])
      {:ok, stop, _} = DateTime.from_iso8601(extra["end_at"])

      hosted =
        Map.get_lazy(context, :self_hosted?, fn ->
          DawarichWeb.LayoutAssigns.self_hosted?(System.get_env())
        end)

      payload = %{
        "user_id" => import.user_id,
        "start_at" => DateTime.to_unix(start),
        "end_at" => DateTime.to_unix(stop),
        "stepping" => "calendar",
        "time_zone" => Dawarich.TimeZoneName.to_iana(context.zone),
        "plan_restricted" =>
          not Dawarich.Entitlements.full_access?(
            repo,
            %{id: import.user_id, plan: plan},
            hosted,
            Snapshot.clock(context)
          )
      }

      {:ok, args} = Dawarich.Visits.SuggestWorker.args_from_command(1, payload)

      publish!(
        repo,
        Dawarich.Visits.SuggestWorker,
        args,
        identity(repo, import.id),
        Snapshot.clock(context)
      )
    end

    :ok
  end

  def run!(repo, import, context, "extract", _) do
    case repo.query!(
           "SELECT source FROM imports WHERE id=$1 AND user_id=$2 AND status<>4",
           [import.id, import.user_id],
           log: false
         ).rows do
      [[source]] when source in [0, 3, 4, 13] ->
        Dawarich.EnhancedImport.NormalWorker.enqueue!(
          repo,
          Map.put(import, :source, source),
          context
        )

      [[_]] ->
        repo.query!(
          "UPDATE imports SET additional_data_extraction_status=4,additional_data_extraction=additional_data_extraction||jsonb_build_object('error_message','Unsupported native extraction source') WHERE id=$1 AND user_id=$2",
          [import.id, import.user_id],
          log: false
        )

      [] ->
        :ok
    end

    :ok
  end

  def identity(repo, id) do
    case repo.query!("SELECT event_id FROM phoenix.import_runs WHERE import_id=$1", [id],
           log: false
         ).rows do
      [[event]] -> Ecto.UUID.load!(event)
      [] -> Dawarich.Achievements.BulkCheck.job_id("import:#{id}")
    end
  end

  def publish!(repo, worker, payload, root, at) do
    event = Dawarich.Achievements.BulkCheck.child_id(root, "#{worker}:#{Jason.encode!(payload)}")

    if repo.query!(
         "SELECT id FROM oban.oban_jobs WHERE worker=$1 AND args->>'event_id'=$2 LIMIT 1",
         [Atom.to_string(worker) |> String.trim_leading("Elixir."), event],
         log: false
       ).rows == [] do
      repo.insert!(worker.new(Map.put(payload, "event_id", event), scheduled_at: at),
        prefix: "oban"
      )
    end

    :ok
  end
end
