defmodule Dawarich.ReleaseOperations.AnomaliesUser do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26

  alias Dawarich.ReleaseOperations, as: Ops
  alias Dawarich.ReleaseOperations.Anomalies
  alias Dawarich.Points.AnomalyBackfillWorker
  alias Dawarich.Users.{RecalculationArgs, RecalculationPeriod}
  alias Dawarich.{I18n, Notifications, LocalTime, UserSettings}
  alias Dawarich.Mail.ExploreFeatures
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @done "anomaly_rules_recalculated_at"
  @failed "anomaly_rules_recalculation_failed_at"
  @prefix "jobs.data_migrations.recalculate_anomalies_user_job."

  def command_type, do: "release.anomalies_user"

  def args_from_command(version, payload) do
    with {:ok, request} <- RecalculationArgs.decode(command_type(), version, payload),
         do: {:ok, %{"version" => 1, "cursor" => %{"request" => request, "rebuild_attempt" => 1}}}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job),
    do: Ops.run(Dawarich.Jobs.repo(), conf.name, __MODULE__, job)

  def step(repo, %{cursor: %{"request" => request}} = op) do
    case repo.query!(
           "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL",
           [request["user_id"]],
           log: false
         ).rows do
      [] ->
        terminal(repo, op, :missing, nil)

      [[settings]] ->
        settings = if is_map(settings), do: settings, else: %{}

        cond do
          Ruby.present?(settings[@done]) ->
            terminal(repo, op, :done, settings)

          not UserSettings.on_unless_off?(%{settings: settings}, "gps_filtering_enabled") ->
            terminal(repo, op, :disabled, settings)

          true ->
            rebuild(repo, op, settings)
        end
    end
  rescue
    _error -> retry_failed(repo, op)
  end

  def mark_failed(repo, id, now) do
    repo.query!(
      """
      UPDATE users SET settings=COALESCE(settings,'{}'::jsonb) || $2::jsonb
      WHERE id=$1 AND deleted_at IS NULL AND NOT jsonb_exists(COALESCE(settings,'{}'::jsonb),$3)
      """,
      [id, %{@failed => DateTime.to_iso8601(now)}, @done],
      log: false
    ).num_rows
  end

  defp rebuild(repo, op, settings) do
    args = backfill_args(op)

    case AnomalyBackfillWorker.run(repo, op.oban, args, op.opts) do
      {:ok, true} ->
        terminal(repo, op, :success, settings)

      {:ok, false} ->
        busy(repo, op)

      {:error, :lock_busy} ->
        busy(repo, op)

      {:error, :execution_busy} ->
        busy(repo, op)

      {:ok, nil} ->
        Ops.commit(repo, op, fn ->
          Oban.insert!(op.oban, AnomalyBackfillWorker.new(args))
          slot!(op)
          :done
        end)
    end
  end

  defp retry_failed(repo, op) do
    if op.cursor["rebuild_attempt"] >= 3 do
      terminal(repo, op, :failed, nil)
    else
      n = op.cursor["rebuild_attempt"]
      base = Integer.pow(n, 4)
      draw = Keyword.get_lazy(op.opts, :jitter_draw, &:rand.uniform/0)
      delay = trunc(base + 2 + base * 0.15 * draw)

      Ops.commit(repo, op, fn ->
        {Map.put(op.cursor, "rebuild_attempt", n + 1), delay}
      end)
    end
  end

  defp busy(repo, op) do
    attempt = op.cursor["request"]["attempt"]

    if attempt >= 8 do
      terminal(repo, op, :failed, nil)
    else
      Ops.commit(repo, op, fn ->
        request = Map.put(op.cursor["request"], "attempt", attempt + 1)
        {op.cursor |> Map.put("request", request) |> Map.put("rebuild_attempt", 1), 900}
      end)
    end
  end

  defp terminal(repo, op, outcome, settings) do
    Ops.commit(repo, op, fn ->
      request = op.cursor["request"]
      now = Keyword.get_lazy(op.opts, :now, &DateTime.utc_now/0)

      if outcome in [:disabled, :success] do
        stamp = local_stamp(repo, now, request["ambient_zone"])

        repo.query!(
          "UPDATE users SET settings=COALESCE(settings,'{}'::jsonb) || $2 WHERE id=$1",
          [request["user_id"], %{@done => stamp}],
          log: false
        )
      end

      if outcome == :failed, do: mark_failed(repo, request["user_id"], now)
      if outcome == :success, do: notify!(repo, request["user_id"], settings)
      if hook = op.opts[:before_terminal], do: hook.()
      slot!(op)
      :done
    end)
  end

  defp slot!(op) do
    id = Ecto.UUID.generate()

    {:ok, args} =
      Anomalies.args_from_command(1, %{
        "limit" => 1,
        "source_job_id" => id,
        "ambient_zone" => op.cursor["request"]["ambient_zone"]
      })

    Oban.insert!(op.oban, Anomalies.new(Map.put(args, "event_id", id)))
  end

  defp backfill_args(op) do
    request = op.cursor["request"]

    id =
      RecalculationPeriod.command_id(
        "release.anomalies_user:#{request["source_job_id"]}:#{request["attempt"]}:#{op.cursor["rebuild_attempt"]}"
      )

    %{
      "user_id" => request["user_id"],
      "reset" => true,
      "notify" => false,
      "rebuild" => "inline",
      "source_job_id" => id,
      "event_id" => id,
      "ambient_zone" => request["ambient_zone"],
      "progress" => %{}
    }
  end

  defp notify!(repo, id, settings) do
    locale = ExploreFeatures.locale(settings, nil)
    {:ok, title} = I18n.t(locale, @prefix <> "gps_noise_re_check_finished")
    {:ok, content} = I18n.t(locale, @prefix <> "rules_recheck_finished")
    Notifications.create!(repo, id, :info, title, content)
  end

  defp local_stamp(repo, now, zone) do
    [[local, offset]] =
      repo.query!(
        """
        SELECT to_char($1::timestamptz AT TIME ZONE $2,'YYYY-MM-DD"T"HH24:MI:SS'),
          extract(epoch FROM (($1::timestamptz AT TIME ZONE $2)-($1::timestamptz AT TIME ZONE 'UTC')))::int
        """,
        [now, zone],
        log: false
      ).rows

    local <> LocalTime.offset(zone, offset, :iso)
  end
end
