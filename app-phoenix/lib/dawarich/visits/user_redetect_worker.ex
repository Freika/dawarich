defmodule Dawarich.Visits.UserRedetectWorker do
  @moduledoc false
  use Oban.Worker, queue: :visit_suggesting, priority: 3, max_attempts: 2

  require Logger

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Tracks.PerUserLock
  alias Dawarich.Visits.{Calendar, HistoryRedetect, Settings, SmartDetect}

  @command_type "visits.user_redetect"
  @max_lock_retries 3
  @lock_retry_seconds 900

  def args_from_command(1, %{"user_id" => user} = payload) when is_integer(user) do
    attempt = Map.get(payload, "lock_attempts", 0)
    zone = Map.get(payload, "time_zone", default_zone())
    run = payload["run_id"]

    if Map.keys(payload) -- ~w(user_id lock_attempts time_zone run_id) == [] and
         is_integer(attempt) and attempt in 0..@max_lock_retries and
         is_binary(zone) and zone != "" and (is_nil(run) or match?({:ok, _}, Ecto.UUID.cast(run))) do
      {:ok, payload |> Map.put("lock_attempts", attempt) |> Map.put("time_zone", zone)}
    else
      {:error, "invalid_payload"}
    end
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: n}), do: Integer.pow(n - 1, 4) + 15 + (:rand.uniform(10) - 1) * n

  def enqueue(repo, user, run_at, parent_event) do
    unless repo.in_transaction?(), do: raise(ArgumentError, "transaction required")

    if Dawarich.Standalone.enabled?() or
         Ownership.lock(repo, "command:" <> @command_type) == :oban do
      publish(
        repo,
        %{"user_id" => user, "lock_attempts" => 0, "time_zone" => default_zone()},
        DateTime.from_unix!(run_at),
        parent_event
      )
    else
      Dawarich.RailsCommands.insert!(repo, "release_user_redetect", %{
        "user_id" => user,
        "run_at" => run_at
      })
    end

    :ok
  end

  def run(repo, %{"user_id" => user, "event_id" => event} = args, opts \\ []) do
    clock = fn -> Keyword.get_lazy(opts, :now, &DateTime.utc_now/0) end

    case repo.query!("SELECT settings,plan FROM users WHERE id=$1 AND deleted_at IS NULL", [user],
           log: false
         ).rows do
      [[settings, plan]] ->
        if Settings.policy(settings).suggestions_enabled and not Processed.done?(repo, event) do
          detect = fn -> redetect(repo, args, %{id: user, plan: plan}, settings, clock) end

          case PerUserLock.with_user_lock(repo, user, detect, Keyword.get(opts, :lock, [])) do
            {:ok, result} -> result
            {:error, :timeout} -> retry_lock(repo, args, clock.())
          end
        else
          :ok
        end

      [] ->
        :ok
    end
  end

  defp retry_lock(repo, args, now) do
    Processed.once(repo, args["event_id"], @command_type, fn ->
      attempt = Map.get(args, "lock_attempts", 0)

      if attempt < @max_lock_retries do
        payload =
          args
          |> Map.delete("event_id")
          |> Map.put("lock_attempts", attempt + 1)
          |> Map.put("run_id", args["run_id"] || args["event_id"])

        publish(repo, payload, DateTime.add(now, @lock_retry_seconds), args["event_id"])
      end

      :ok
    end)
  end

  defp redetect(repo, args, user, settings, clock) do
    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      [[min_ts, max_ts]] =
        repo.query!(
          "SELECT min(timestamp),max(timestamp) FROM points WHERE user_id=$1",
          [user.id],
          log: false
        ).rows

      HistoryRedetect.purge(repo, user.id, min_ts, max_ts)

      failed =
        if min_ts do
          policy = %{
            "time_zone" => args["time_zone"] || default_zone(),
            "plan_restricted" =>
              not Dawarich.Entitlements.full_access?(
                repo,
                user,
                DawarichWeb.LayoutAssigns.self_hosted?(),
                clock.()
              )
          }

          repo
          |> Calendar.redetect_months(policy["time_zone"], min_ts, max_ts)
          |> Enum.map(fn [start, stop] -> failed_month?(repo, user.id, start, stop, policy) end)
          |> Enum.any?()
        else
          false
        end

      if min_ts, do: HistoryRedetect.backfill(repo, user.id, Settings.policy(settings))

      Processed.once(repo, args["event_id"], @command_type, fn ->
        if not failed do
          repo.query!(
            "UPDATE users SET visits_redetected_at=$2,updated_at=$2 WHERE id=$1 AND deleted_at IS NULL",
            [user.id, DateTime.to_naive(clock.())],
            log: false
          )
        end

        :ok
      end)
    end
  end

  defp failed_month?(repo, user, start, stop, policy) do
    SmartDetect.run(repo, user, start, stop, policy).skipped_ranges != []
  rescue
    error ->
      Logger.error("event=visits.user_redetect_month_failed type=#{inspect(error.__struct__)}")

      unless DawarichWeb.LayoutAssigns.self_hosted?(),
        do: Sentry.capture_exception(error, stacktrace: __STACKTRACE__, handled: true)

      true
  end

  defp publish(repo, payload, due, parent) do
    repo.query!(
      "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6)",
      [
        Ecto.UUID.bingenerate(),
        @command_type,
        payload,
        %{"producer" => "Phoenix UserRedetect", "parent_event_id" => parent},
        payload["user_id"],
        due
      ],
      log: false
    )
  end

  defp default_zone,
    do: Dawarich.TimeZoneName.to_iana(System.get_env("TIME_ZONE", "Europe/Berlin"))
end
