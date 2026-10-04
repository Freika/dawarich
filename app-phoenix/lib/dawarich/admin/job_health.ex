defmodule Dawarich.Admin.JobHealth do
  @moduledoc false

  @stale 60
  @overdue 300
  @unknown %{"status" => "unknown", "alarm" => false}
  @owners_sql "SELECT key, owner, pinned, updated_at, updated_by FROM phoenix.job_owners ORDER BY key"
  @nodes_sql "SELECT node, started_at, beat_at FROM phoenix.runtime_nodes ORDER BY node"
  @oban_sql "SELECT worker, state, count(*)::integer AS count FROM oban.oban_jobs GROUP BY worker, state ORDER BY worker, state"
  @flags_sql """
  SELECT
    EXISTS (SELECT 1 FROM phoenix.runtime_nodes WHERE node = $1 AND beat_at > now() - make_interval(secs => $2)) AS this_fresh,
    EXISTS (SELECT 1 FROM phoenix.runtime_nodes WHERE beat_at > now() - make_interval(secs => $2)) AS any_fresh,
    EXISTS (SELECT 1 FROM phoenix.job_owners WHERE owner = 'oban') AS oban_owns
  """
  @outbox_sql """
  SELECT
    count(*) FILTER (WHERE state = 'pending' AND scheduled_at <= now())::integer AS due,
    count(*) FILTER (WHERE state = 'pending' AND scheduled_at > now())::integer AS scheduled,
    count(*) FILTER (WHERE state = 'quarantined')::integer AS quarantined,
    EXTRACT(EPOCH FROM now() - min(scheduled_at) FILTER (WHERE state = 'pending' AND scheduled_at <= now()))::integer AS oldest_due_seconds
  FROM job_outbox
  """
  @commands_sql """
  SELECT
    (SELECT count(*) FROM phoenix.rails_commands WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now()))::integer AS due,
    (SELECT count(*) FROM phoenix.rails_commands WHERE leased_until >= now())::integer AS leased,
    (SELECT count(*) FROM phoenix.rails_commands WHERE attempts > 0 AND (leased_until IS NULL OR leased_until < now()))::integer AS retrying,
    (SELECT count(*) FROM phoenix.rails_commands_dead)::integer AS dead,
    (SELECT EXTRACT(EPOCH FROM now() - min(available_at))::integer FROM phoenix.rails_commands WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now())) AS oldest_due_seconds
  """
  @orders %{
    "outbox" => ~w(due scheduled quarantined oldest_due_seconds),
    "owners" => ~w(key owner pinned updated_at updated_by),
    "nodes" => ~w(node started_at beat_at),
    "oban" => ~w(worker state count),
    "rails_commands" => ~w(due leased retrying dead oldest_due_seconds)
  }
  @gauge_keys ~w(outbox owners nodes oban rails_commands)

  def load(public_repo, jobs_repo, node) do
    %{summary: summary(public_repo, jobs_repo, node), gauges: gauges(public_repo, jobs_repo)}
  end

  def pretty(%{"tables" => true} = gauges) do
    @gauge_keys
    |> Enum.map(fn key -> {key, ordered(gauges[key], @orders[key])} end)
    |> Jason.OrderedObject.new()
    |> Jason.encode!(pretty: true)
  end

  def pretty(_), do: nil

  defp summary(public_repo, jobs_repo, node) do
    flags =
      read(jobs_repo, fn ->
        if table?(jobs_repo, "phoenix.job_owners"),
          do: one(jobs_repo, @flags_sql, [node || "", @stale])
      end)

    if flags do
      overdue =
        read(public_repo, fn ->
          [[overdue]] =
            public_repo.query!(
              "SELECT EXISTS(SELECT 1 FROM job_outbox WHERE state = 'pending' AND scheduled_at < now() - make_interval(secs => $1))",
              [@overdue],
              log: false
            ).rows

          overdue
        end)

      status =
        cond do
          blank?(node) -> "absent"
          flags["this_fresh"] -> "ok"
          true -> "stale"
        end

      %{"status" => status, "alarm" => (flags["oban_owns"] and not flags["any_fresh"]) or overdue}
    else
      %{"status" => if(blank?(node), do: "absent", else: "stale"), "alarm" => false}
    end
  rescue
    _ -> @unknown
  end

  defp gauges(public_repo, jobs_repo) do
    jobs =
      read(jobs_repo, fn ->
        if table?(jobs_repo, "phoenix.job_owners") do
          %{
            "tables" => true,
            "owners" => all(jobs_repo, @owners_sql),
            "nodes" => all(jobs_repo, @nodes_sql),
            "oban" =>
              if(table?(jobs_repo, "oban.oban_jobs"), do: all(jobs_repo, @oban_sql), else: []),
            "rails_commands" =>
              if(table?(jobs_repo, "phoenix.rails_commands_dead"),
                do: one(jobs_repo, @commands_sql),
                else: nil
              )
          }
        else
          %{"tables" => false}
        end
      end)

    if jobs["tables"],
      do: Map.put(jobs, "outbox", read(public_repo, fn -> one(public_repo, @outbox_sql) end)),
      else: jobs
  rescue
    _ -> %{"tables" => "unknown"}
  end

  defp read(repo, fun) do
    {:ok, value} =
      repo.transaction(fn ->
        repo.query!("SET LOCAL statement_timeout = '500ms'", [], log: false)
        fun.()
      end)

    value
  end

  defp table?(repo, table) do
    [[present]] = repo.query!("SELECT to_regclass('#{table}') IS NOT NULL", [], log: false).rows
    present
  end

  defp one(repo, sql, params \\ []), do: List.first(all(repo, sql, params))

  defp all(repo, sql, params \\ []) do
    %{columns: columns, rows: rows} = repo.query!(sql, params, log: false)
    Enum.map(rows, fn row -> Map.new(Enum.zip(columns, Enum.map(row, &json_value/1))) end)
  end

  defp json_value(%DateTime{} = date), do: Calendar.strftime(date, "%Y-%m-%d %H:%M:%S +0000")
  defp json_value(%NaiveDateTime{} = date), do: Calendar.strftime(date, "%Y-%m-%d %H:%M:%S +0000")
  defp json_value(value), do: value
  defp blank?(node), do: is_nil(node) or (is_binary(node) and String.trim(node) == "")
  defp ordered(nil, _keys), do: nil
  defp ordered(rows, keys) when is_list(rows), do: Enum.map(rows, &ordered(&1, keys))

  defp ordered(row, keys),
    do: Jason.OrderedObject.new(for key <- keys, Map.has_key?(row, key), do: {key, row[key]})
end
