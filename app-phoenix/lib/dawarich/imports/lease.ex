defmodule Dawarich.Imports.Lease do
  @moduledoc false
  alias Dawarich.Imports.LeaseLost
  alias Dawarich.Jobs.Ownership
  alias Dawarich.State
  @lane "command:imports.process_gpx"
  @worker "Dawarich.Imports.ProcessGpxWorker"

  def with_import(
        repo,
        %Oban.Job{id: job_id, attempt: attempt, args: args},
        import,
        fun,
        opts \\ []
      )
      when is_integer(job_id) and job_id > 0 and is_integer(attempt) and attempt > 0 do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "Import lease cannot run inside an enclosing transaction")

    event = Ecto.UUID.dump!(Map.fetch!(args, "event_id"))

    unless args["import_id"] == import.id and args["user_id"] == import.user_id,
      do: raise(ArgumentError, "Import command identity does not match its context")

    lease = %{
      repo: repo,
      import: import,
      job_id: job_id,
      attempt: attempt,
      event: event,
      event_id: args["event_id"],
      token: Ecto.UUID.dump!(Ecto.UUID.generate()),
      scope: make_ref(),
      lane: Keyword.get(opts, :lane, @lane),
      worker: Keyword.get(opts, :worker, @worker),
      sources: Keyword.get(opts, :sources, [4]),
      terminal_statuses: Keyword.get(opts, :terminal_statuses, [2])
    }

    case State.Lease.with_lease(repo, "import:#{import.id}", fn -> run(lease, fun) end,
           timeout_ms: 0
         ) do
      {:ok, result} -> result
      {:error, :timeout} -> {:skip, :busy}
    end
  end

  defp run(lease, fun) do
    lease = Map.put(lease, :mode, if(terminal_resume?(lease), do: :terminal, else: :processing))

    try do
      case claim(lease) do
        :ok ->
          Process.put({__MODULE__, lease.scope}, true)
          {:ok, fun.(lease)}

        reason ->
          {:skip, reason}
      end
    after
      Process.delete({__MODULE__, lease.scope})
    end
  end

  def effect!(lease, fun) when is_function(fun, 0) do
    guarded_effect!(lease, fun, :processing)
  end

  def terminal_effect!(lease, fun) when is_function(fun, 0) do
    guarded_effect!(lease, fun, :terminal)
  end

  defp guarded_effect!(lease, fun, mode) do
    unless Process.get({__MODULE__, lease.scope}), do: raise(LeaseLost)

    case lease.repo.transaction(fn ->
           unless current?(Map.put(lease, :mode, mode)) and token_current?(lease),
             do: raise(LeaseLost)

           fun.()
         end) do
      {:ok, value} -> value
      {:error, _} -> raise LeaseLost
    end
  end

  defp claim(lease) do
    result =
      lease.repo.transaction(fn ->
        unless current?(lease), do: lease.repo.rollback(:unavailable)
        if legacy_metadata?(lease), do: lease.repo.rollback(:legacy)

        result =
          lease.repo.query!(
            """
            INSERT INTO phoenix.import_runs (import_id,user_id,event_id,job_id,attempt,token,updated_at)
            VALUES ($1,$2,$3,$4,$5,$6,now())
            ON CONFLICT (import_id) DO UPDATE SET
              user_id=EXCLUDED.user_id, job_id=EXCLUDED.job_id, attempt=EXCLUDED.attempt,
              token=EXCLUDED.token, updated_at=EXCLUDED.updated_at
            WHERE import_runs.event_id=EXCLUDED.event_id
            RETURNING token
            """,
            values(lease),
            log: false
          )

        if result.num_rows == 0, do: lease.repo.rollback(:conflict)
        :ok
      end)

    case result do
      {:ok, :ok} -> :ok
      {:error, reason} -> reason
    end
  end

  defp current?(lease) do
    Ownership.lock(lease.repo, lease.lane) == :oban and job_current?(lease) and
      user_current?(lease) and import_current?(lease)
  end

  defp user_current?(lease) do
    lease.repo.query!(
      "SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL FOR SHARE",
      [lease.import.user_id],
      log: false
    ).rows == [[lease.import.user_id]]
  end

  defp job_current?(lease) do
    case lease.repo.query!(
           "SELECT state,attempt,worker,args FROM oban.oban_jobs WHERE id=$1 FOR SHARE",
           [lease.job_id],
           log: false
         ).rows do
      [["executing", attempt, worker, args]] ->
        worker == lease.worker and attempt == lease.attempt and args["event_id"] == lease.event_id and
          args["import_id"] == lease.import.id and args["user_id"] == lease.import.user_id

      _ ->
        false
    end
  end

  defp import_current?(lease) do
    case lease.repo.query!(
           "SELECT user_id,source,status FROM imports WHERE id=$1 FOR UPDATE",
           [lease.import.id],
           log: false
         ).rows do
      [[user, source, status]] ->
        user == lease.import.user_id and source in lease.sources and
          case Map.get(lease, :mode, :processing) do
            :processing -> status in [0, 1, 3]
            :terminal -> status in lease.terminal_statuses and terminal_resume?(lease)
          end

      _ ->
        false
    end
  end

  defp terminal_resume?(lease) do
    lease.repo.query!(
      "SELECT 1 FROM phoenix.import_runs WHERE import_id=$1 AND user_id=$2 AND event_id=$3 AND phase='terminal'",
      [lease.import.id, lease.import.user_id, lease.event],
      log: false
    ).rows == [[1]]
  end

  defp legacy_metadata?(lease) do
    [[raw, extraction]] =
      lease.repo.query!(
        "SELECT raw_data,additional_data_extraction FROM imports WHERE id=$1",
        [lease.import.id],
        log: false
      ).rows

    not (is_nil(raw) or is_map(raw)) or not is_map(extraction)
  end

  defp token_current?(lease) do
    lease.repo.query!(
      """
      SELECT token FROM phoenix.import_runs
      WHERE import_id=$1 AND user_id=$2 AND event_id=$3 AND job_id=$4 AND attempt=$5 AND token=$6
      FOR SHARE
      """,
      values(lease),
      log: false
    ).rows == [[lease.token]]
  end

  defp values(lease),
    do: [
      lease.import.id,
      lease.import.user_id,
      lease.event,
      lease.job_id,
      lease.attempt,
      lease.token
    ]
end
