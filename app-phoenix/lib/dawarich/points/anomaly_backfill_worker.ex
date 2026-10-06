defmodule Dawarich.Points.AnomalyBackfillWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 26

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Points.{AnomalyBackfill, AnomalyBackfillProgress}
  alias Dawarich.Users.{RecalculationArgs, RecalculationPeriod, RecalculateWorker}
  alias Dawarich.RailsCommands
  alias Dawarich.State.Lease

  def args_from_command(version, payload),
    do: RecalculationArgs.decode("points.anomaly_backfill", version, payload)

  def enqueue(repo, payload) do
    cond do
      Dawarich.Standalone.enabled?() ->
        Dawarich.Points.NativeEffects.enqueue(
          repo,
          __MODULE__,
          Map.put(payload, "event_id", payload["source_job_id"])
        )

      Ownership.lock(repo, "command:points.anomaly_backfill") == :oban ->
        repo.query!(
          "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),'points.anomaly_backfill',1,$1,$2,$3,now())",
          [payload, %{"producer" => "Phoenix Point Anomaly API"}, payload["user_id"]],
          log: false
        )

        :ok

      true ->
        RailsCommands.insert!(repo, "points.anomaly_backfill", payload)
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}) do
    case run(Dawarich.Jobs.repo(), conf.name, args) do
      {:ok, true} -> :ok
      {:ok, false} -> :ok
      {:ok, nil} -> {:snooze, 3}
      {:error, :execution_busy} -> {:snooze, 3}
      error -> error
    end
  end

  def rebuild_id(args),
    do: RecalculationPeriod.command_id("anomaly_backfill.rebuild:#{args["source_job_id"]}")

  def run(repo, oban, args, opts \\ []) do
    case Lease.with_lease(
           repo,
           "points.anomaly_backfill:" <> args["event_id"],
           fn ->
             if Processed.done?(repo, args["event_id"]) do
               {:ok, true}
             else
               complete = fn fence -> complete(repo, oban, args, opts, fence) end

               backfill_opts =
                 opts
                 |> Keyword.put(:complete, complete)
                 |> Keyword.put_new(:lease, timeout_ms: 0)

               case AnomalyBackfill.run(repo, args, backfill_opts) do
                 {:error, :busy} -> {:ok, false}
                 {:ok, {:error, _} = error} -> error
                 other -> other
               end
             end
           end,
           Keyword.get(opts, :lease, [])
         ) do
      {:ok, result} -> result
      {:error, :timeout} -> {:error, :execution_busy}
    end
  end

  defp complete(repo, oban, args, opts, fence) do
    payload = %{
      "user_id" => args["user_id"],
      "year" => nil,
      "notify" => args["notify"],
      "job_queue" => nil,
      "source_job_id" => rebuild_id(args),
      "ambient_zone" => args["ambient_zone"]
    }

    result =
      if args["reset"] and args["rebuild"] == "inline" do
        inline =
          Map.merge(payload, %{"job_queue" => "low_priority", "event_id" => rebuild_id(args)})

        RecalculateWorker.inline(repo, oban, inline, fence, opts)
      else
        :ok
      end

    if result == :ok do
      {:ok, true} =
        repo.transaction(fn ->
          fence.()

          if args["reset"] do
            if args["rebuild"] == "async", do: route!(repo, "users.recalculate_data", payload)

            [[oldest]] =
              repo.query!("SELECT min(timestamp) FROM points WHERE user_id=$1", [args["user_id"]],
                log: false
              ).rows

            if oldest != nil,
              do:
                route!(repo, "achievements.check", %{
                  "user_id" => args["user_id"],
                  "notify" => args["notify"],
                  "oldest_timestamp" => oldest
                })
          end

          AnomalyBackfillProgress.clear!(repo, args)
          Processed.mark!(repo, args["event_id"], "points.anomaly_backfill")
          fence.()
          true
        end)

      true
    else
      result
    end
  end

  defp route!(repo, kind, payload) do
    if Dawarich.Standalone.enabled?() do
      {worker, args} =
        case kind do
          "users.recalculate_data" ->
            {RecalculateWorker, Map.put(payload, "event_id", payload["source_job_id"])}

          "achievements.check" ->
            {Dawarich.Achievements.CheckWorker, payload}
        end

      Dawarich.Points.NativeEffects.enqueue(repo, worker, args)
    else
      case Ownership.lock(repo, "command:" <> kind) do
        :sidekiq ->
          RailsCommands.insert!(repo, kind, Map.put(payload, "run_at", System.os_time(:second)))

        :oban ->
          repo.query!(
            """
            INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at)
            VALUES($1,$2,1,$3,$4,$5,NOW())
            """,
            [
              Ecto.UUID.dump!(payload["source_job_id"] || Ecto.UUID.generate()),
              kind,
              payload,
              %{"producer" => "Phoenix Points::AnomalyBackfill"},
              payload["user_id"]
            ],
            log: false
          )
      end
    end

    :ok
  end
end
