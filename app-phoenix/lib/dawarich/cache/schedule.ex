defmodule Dawarich.Cache.Schedule do
  @moduledoc false

  alias Dawarich.RailsCommands

  def preheat_user(repo, user_id, opts \\ []) do
    payload = %{
      "user_id" => user_id,
      "time_zone" => Keyword.get(opts, :time_zone, System.get_env("TIME_ZONE", "Europe/Berlin")),
      "source_job_id" => Keyword.get_lazy(opts, :source_job_id, &Ecto.UUID.generate/0),
      "run_at" =>
        Keyword.get_lazy(opts, :clock, fn -> System.os_time(:second) end) +
          Keyword.get(opts, :schedule_in, 0)
    }

    {:ok, :ok} =
      repo.transaction(fn ->
        if Keyword.get(opts, :accepted, false) or
             Dawarich.Jobs.Ownership.lock(repo, "command:cache.preheat_user") == :oban do
          args = payload |> Map.delete("run_at") |> Map.put("event_id", payload["source_job_id"])

          {:ok, _} =
            Dawarich.Cache.PreheatUserWorker.args_from_command(1, Map.delete(args, "event_id"))

          repo.query!(
            "SELECT pg_advisory_xact_lock(hashtextextended($1,0))",
            [payload["source_job_id"]],
            log: false
          )

          existing =
            repo.query!(
              "SELECT 1 FROM oban.oban_jobs WHERE worker='Dawarich.Cache.PreheatUserWorker' AND args->>'event_id'=$1 LIMIT 1",
              [payload["source_job_id"]],
              log: false
            ).rows

          if existing == [] and not Dawarich.Jobs.Processed.done?(repo, payload["source_job_id"]) do
            repo.insert!(
              Dawarich.Cache.PreheatUserWorker.new(args,
                scheduled_at: DateTime.from_unix!(payload["run_at"])
              ),
              prefix: "oban"
            )
          end

          :ok
        else
          RailsCommands.insert!(repo, "cache.preheat_user", payload)
        end
      end)

    :ok
  end
end
