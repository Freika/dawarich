defmodule Dawarich.Jobs.Drain do
  @moduledoc false
  use GenServer

  alias Dawarich.Jobs.{Claimer, Registry}

  @counts """
  SELECT
    (SELECT count(*) FROM job_outbox WHERE state = 'pending')::integer AS pending_outbox,
    (SELECT count(*) FROM job_outbox WHERE state = 'pending' AND scheduled_at > now())::integer AS future_outbox,
    (SELECT count(*) FROM job_outbox WHERE state = 'quarantined')::integer AS quarantined,
    (SELECT count(*) FROM phoenix.rails_commands)::integer AS reverse_pending,
    (SELECT count(*) FROM phoenix.rails_commands WHERE available_at > now())::integer AS reverse_future,
    (SELECT count(*) FROM phoenix.rails_commands WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now()))::integer AS reverse_due,
    (SELECT count(*) FROM phoenix.rails_commands WHERE leased_until >= now())::integer AS reverse_leased,
    (SELECT count(*) FROM phoenix.rails_commands WHERE attempts > 0 AND (leased_until IS NULL OR leased_until < now()))::integer AS reverse_retrying,
    (SELECT count(*) FROM phoenix.rails_commands_dead)::integer AS reverse_dead,
    (SELECT count(*) FROM phoenix.release_operations WHERE status <> 'completed')::integer AS release_pending,
    (SELECT count(*) FROM oban.oban_jobs WHERE state NOT IN ('completed', 'cancelled'))::integer AS incomplete_oban,
    (SELECT count(*) FROM phoenix.track_generations g WHERE status <> 'completed' OR completed_chunks < total_chunks OR EXISTS (SELECT 1 FROM phoenix.track_generation_chunks c WHERE c.generation_id = g.id AND c.status <> 'completed'))::integer AS unfinished_generations,
    (SELECT count(*) FROM unnest($1::text[]) AS expected(key) LEFT JOIN phoenix.job_owners o USING (key) WHERE o.key IS NULL)::integer AS missing_owners,
    (SELECT count(*) FROM phoenix.job_owners WHERE key = ANY($1) AND owner <> 'oban')::integer AS mixed_owners,
    (SELECT count(*) FROM phoenix.job_owners WHERE NOT (key = ANY($1)))::integer AS unknown_owners,
    (SELECT count(*) FROM phoenix.job_owners WHERE key = ANY($1) AND (owner <> 'sidekiq' OR NOT pinned))::integer AS unpinned_rollback_owners,
    (SELECT count(*) FROM phoenix.job_owners WHERE owner = 'oban')::integer AS oban_owners,
    (SELECT count(*) FROM phoenix.runtime_nodes WHERE beat_at > now() - interval '60 seconds')::integer AS fresh_nodes
  """

  @debt ~w(pending_outbox quarantined reverse_pending reverse_dead release_pending)a
  @incomplete "SELECT worker, state, count(*)::integer AS count FROM oban.oban_jobs WHERE state NOT IN ('completed', 'cancelled') GROUP BY worker, state ORDER BY worker, state"

  def status(repo) do
    {:ok, status} =
      repo.transaction(fn ->
        repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ", [], log: false)
        repo.query!("SET LOCAL statement_timeout = '500ms'", [], log: false)

        %{columns: columns, rows: [values]} =
          repo.query!(@counts, [Enum.map(Registry.entries(), & &1.key)], log: false)

        counts = Map.new(Enum.zip(Enum.map(columns, &String.to_atom/1), values))
        legacy = Claimer.legacy_scheduler_counts(repo)
        common = Enum.filter(@debt, &(counts[&1] > 0)) |> Enum.map(&Atom.to_string/1)

        common =
          if Enum.any?(legacy, &(&1.incomplete > 0)),
            do: ["legacy_schedulers" | common],
            else: common

        forward = common ++ reasons(counts, ~w(missing_owners mixed_owners unknown_owners)a)

        forward =
          if counts.oban_owners > 0 and counts.fresh_nodes == 0,
            do: ["heartbeat_invalid" | forward],
            else: forward

        producers =
          Enum.map(Dawarich.RailsCommands.closure_kinds(), &%{kind: &1, status: "BLOCKED"})

        forward = if producers == [], do: forward, else: ["residual_producers" | forward]

        binary =
          common ++
            reasons(
              counts,
              ~w(incomplete_oban unfinished_generations missing_owners unknown_owners unpinned_rollback_owners)a
            )

        shutdown = forward ++ reasons(counts, ~w(incomplete_oban unfinished_generations)a)

        %{
          shutdown: result(shutdown),
          shutdown_reasons: Enum.sort(shutdown),
          certainty: if("heartbeat_invalid" in forward, do: "UNKNOWN", else: "OBSERVED"),
          forward: result(forward),
          binary_rollback: result(binary),
          observation: true,
          forward_reasons: Enum.sort(forward),
          binary_reasons: Enum.sort(binary),
          counts: counts,
          legacy_schedulers: legacy,
          incomplete_workers: objects(repo, @incomplete),
          producer_kinds: producers
        }
      end)

    status
  rescue
    _ ->
      %{
        shutdown: "BLOCKED",
        shutdown_reasons: ["database_unreadable"],
        certainty: "UNKNOWN",
        forward: "BLOCKED",
        binary_rollback: "BLOCKED",
        observation: true,
        forward_reasons: ["database_unreadable"],
        binary_reasons: ["database_unreadable"]
      }
  end

  defp reasons(counts, keys),
    do: keys |> Enum.filter(&(counts[&1] > 0)) |> Enum.map(&Atom.to_string/1)

  defp result([]), do: "OBSERVED_EMPTY"
  defp result(_), do: "BLOCKED"

  defp objects(repo, sql) do
    %{columns: columns, rows: rows} = repo.query!(sql, [], log: false)
    Enum.map(rows, &Map.new(Enum.zip(columns, &1)))
  end

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, Keyword.get(opts, :oban, Oban)}
  end

  @impl true
  def terminate(_reason, oban) do
    Oban.pause_all_queues(oban, local_only: true)
  catch
    _kind, _reason -> :ok
  end
end
