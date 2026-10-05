defmodule Dawarich.CLI.Jobs do
  @moduledoc false

  import Dawarich.CLI, only: [puts: 2, fail: 2]

  alias Dawarich.ReleaseOperations
  alias Dawarich.Jobs.Claimer
  alias Jason.OrderedObject, as: O

  @flags """
  SELECT
    EXISTS (SELECT 1 FROM phoenix.runtime_nodes WHERE node = $1 AND beat_at > now() - make_interval(secs => 60)),
    EXISTS (SELECT 1 FROM phoenix.runtime_nodes WHERE beat_at > now() - make_interval(secs => 60)),
    EXISTS (SELECT 1 FROM phoenix.job_owners WHERE owner = 'oban'),
    EXISTS (SELECT 1 FROM job_outbox WHERE state = 'pending' AND scheduled_at < now() - make_interval(secs => 300))
  """
  @outbox """
  SELECT
    count(*) FILTER (WHERE state = 'pending' AND scheduled_at <= now())::integer AS due,
    count(*) FILTER (WHERE state = 'pending' AND scheduled_at > now())::integer AS scheduled,
    count(*) FILTER (WHERE state = 'quarantined')::integer AS quarantined,
    EXTRACT(EPOCH FROM now() - min(scheduled_at) FILTER (WHERE state = 'pending' AND scheduled_at <= now()))::integer AS oldest_due_seconds
  FROM job_outbox
  """
  @owners "SELECT key, owner, pinned, updated_at, updated_by FROM phoenix.job_owners ORDER BY key"
  @nodes "SELECT node, started_at, beat_at FROM phoenix.runtime_nodes ORDER BY node"
  @oban "SELECT worker, state, count(*)::integer AS count FROM oban.oban_jobs GROUP BY worker, state ORDER BY worker, state"
  @rails_commands """
  SELECT
    (SELECT count(*) FROM phoenix.rails_commands
       WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now()))::integer AS due,
    (SELECT count(*) FROM phoenix.rails_commands WHERE leased_until >= now())::integer AS leased,
    (SELECT count(*) FROM phoenix.rails_commands
       WHERE attempts > 0 AND (leased_until IS NULL OR leased_until < now()))::integer AS retrying,
    (SELECT count(*) FROM phoenix.rails_commands_dead)::integer AS dead,
    (SELECT EXTRACT(EPOCH FROM now() - min(available_at))::integer FROM phoenix.rails_commands
       WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now())) AS oldest_due_seconds
  """
  @usage "usage: dawarich jobs resume OPERATION_ID"

  def status([], ctx) do
    node = ctx.env["DAWARICH_PHOENIX_NODE"]
    node = if node in [nil, ""], do: nil, else: node
    json = O.new([{"summary", summary(ctx.repo, node)}, {"gauges", gauges(ctx.repo)}])
    puts(ctx, Jason.encode!(json, pretty: true))
    0
  end

  def status(_args, ctx), do: fail(ctx, "usage: dawarich jobs status")

  def resume([id], ctx) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, _job} <- ReleaseOperations.resume(ctx.repo, oban(ctx), uuid) do
      puts(ctx, "#{uuid}: resumed")
      0
    else
      :error -> fail(ctx, @usage)
      {:error, :not_resumable} -> fail(ctx, "#{id} is not a failed or stalled release operation")
    end
  end

  def resume(_args, ctx), do: fail(ctx, @usage)

  defp summary(repo, node) do
    case read(repo, fn -> if table?(repo, "phoenix.job_owners"), do: flags(repo, node) end) do
      {:ok, [this, any, oban, overdue]} ->
        O.new(status: status_of(node, this), alarm: (oban and not any) or overdue)

      {:ok, nil} ->
        O.new(status: if(node, do: "stale", else: "absent"), alarm: false)

      :error ->
        O.new(status: "unknown", alarm: false)
    end
  end

  defp status_of(nil, _fresh), do: "absent"
  defp status_of(_node, true), do: "ok"
  defp status_of(_node, false), do: "stale"

  defp flags(repo, node), do: hd(repo.query!(@flags, [node || ""], log: false).rows)

  defp gauges(repo) do
    case read(repo, fn ->
           if table?(repo, "phoenix.job_owners"), do: full(repo), else: O.new(tables: false)
         end) do
      {:ok, gauges} -> gauges
      :error -> O.new(tables: "unknown")
    end
  end

  defp full(repo) do
    O.new(
      tables: true,
      outbox: one(repo, @outbox),
      owners: all(repo, @owners),
      nodes: all(repo, @nodes),
      oban: if(table?(repo, "oban.oban_jobs"), do: all(repo, @oban), else: []),
      legacy_schedulers:
        if(table?(repo, "oban.oban_jobs"),
          do: Claimer.legacy_scheduler_counts(repo),
          else: "unknown"
        ),
      rails_commands:
        if(table?(repo, "phoenix.rails_commands_dead"), do: one(repo, @rails_commands))
    )
  end

  defp read(repo, fun) do
    repo.transaction(fn ->
      repo.query!("SET LOCAL statement_timeout = '500ms'", [], log: false)
      fun.()
    end)
  rescue
    _ -> :error
  end

  defp table?(repo, name),
    do: repo.query!("SELECT to_regclass($1) IS NOT NULL", [name], log: false).rows == [[true]]

  defp one(repo, sql), do: repo |> objects(sql) |> hd()
  defp all(repo, sql), do: objects(repo, sql)

  defp objects(repo, sql) do
    %{columns: columns, rows: rows} = repo.query!(sql, [], log: false)
    Enum.map(rows, fn row -> O.new(Enum.zip(columns, Enum.map(row, &value/1))) end)
  end

  defp value(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S %z")
  defp value(other), do: other

  defp oban(%{oban: oban}), do: oban

  defp oban(ctx) do
    {:ok, _} = Application.ensure_all_started(:oban)

    {:ok, _} =
      Oban.start_link(
        name: Dawarich.CLI.Oban,
        repo: ctx.repo,
        prefix: "oban",
        notifier: Oban.Notifiers.PG,
        peer: false,
        queues: [],
        plugins: [],
        stager: false
      )

    Dawarich.CLI.Oban
  end
end
