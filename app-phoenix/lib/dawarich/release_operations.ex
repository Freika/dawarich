defmodule Dawarich.ReleaseOperations do
  @moduledoc false

  require Logger

  @start """
  INSERT INTO phoenix.release_operations (id, command_type, cursor) VALUES ($1, $2, $3)
  ON CONFLICT (id) DO NOTHING
  """
  @load "SELECT cursor, status FROM phoenix.release_operations WHERE id = $1"
  @advance """
  UPDATE phoenix.release_operations SET cursor = $3, updated_at = now()
  WHERE id = $1 AND status = 'running' AND cursor = $2
  """
  @complete """
  UPDATE phoenix.release_operations SET status = 'completed', updated_at = now(), completed_at = now()
  WHERE id = $1 AND status = 'running' AND cursor = $2
  """
  @fail """
  UPDATE phoenix.release_operations SET status = 'failed', error = $3, updated_at = now()
  WHERE id = $1 AND status = 'running' AND cursor = $2
  """
  @retry """
  UPDATE phoenix.release_operations SET status = 'running', error = NULL, updated_at = now()
  WHERE id = $1 AND status = 'failed' AND cursor = $2
  """
  @resume """
  UPDATE phoenix.release_operations SET status = 'running', error = NULL, updated_at = now()
  WHERE id = $1 AND (status = 'failed' OR status = 'running' AND NOT EXISTS (
    SELECT 1 FROM oban.oban_jobs
    WHERE state IN ('available', 'suspended', 'scheduled', 'executing', 'retryable')
      AND (args->>'operation_id' = $1::text OR args->>'event_id' = $1::text)
  ))
  RETURNING command_type, cursor
  """
  @user "SELECT EXISTS (SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL)"

  def run(repo, oban, worker, %Oban.Job{args: args} = job, opts \\ []) do
    with %{"version" => 1, "cursor" => %{} = cursor} <- args,
         id when is_binary(id) <- args["operation_id"] || args["event_id"] do
      op = %{id: id, cursor: cursor, worker: worker, oban: oban, opts: opts}
      repo.query!(@start, [dump(id), worker.command_type(), cursor], log: false)

      if opts[:fail_on_error], do: repo.query!(@retry, [dump(id), cursor], log: false)

      case repo.query!(@load, [dump(id)], log: false).rows do
        [[^cursor, "running"]] -> op |> step(repo, job) |> settle()
        _ -> :ok
      end
    else
      _ -> {:cancel, :unsupported_version}
    end
  end

  def commit(repo, op, fun) do
    repo.transaction(fn ->
      next = fun.()
      if transition(repo, op, next) != 1, do: repo.rollback(:stale)
      with {cursor, delay} <- next, do: insert!(op, op.id, cursor, delay)
      :ok
    end)
  end

  def spawn!(op, cursor), do: insert!(op, Ecto.UUID.generate(), cursor, 0)

  def resume(repo, oban, id, commands \\ &Dawarich.Jobs.Registry.command/1) do
    repo.transaction(fn ->
      with [[type, cursor]] <- repo.query!(@resume, [dump(id)], log: false).rows,
           {:ok, worker} <- commands.(type) do
        insert!(%{oban: oban, worker: worker}, id, cursor, 0)
      else
        _ -> repo.rollback(:not_resumable)
      end
    end)
  end

  def value(repo, sql, params \\ []) do
    [[value]] = repo.query!(sql, params, log: false).rows
    value
  end

  def ids(repo, sql, params), do: List.flatten(repo.query!(sql, params, log: false).rows)

  def user?(repo, user_id), do: value(repo, @user, [user_id])

  def no_payload(1, payload) when map_size(payload) == 0, do: {:ok, %{"version" => 1}}
  def no_payload(1, _payload), do: {:error, "invalid_payload"}
  def no_payload(_version, _payload), do: {:error, "unsupported_version"}

  defp step(op, repo, job) do
    op.worker.step(repo, op)
  rescue
    exception ->
      cond do
        op.opts[:fail_on_error] -> fail!(repo, op, inspect(exception.__struct__))
        job.attempt >= job.max_attempts -> fail!(repo, op, Exception.message(exception))
        true -> :ok
      end

      reraise exception, __STACKTRACE__
  end

  defp settle({:error, :stale}), do: :ok
  defp settle({:ok, _}), do: :ok
  defp settle(other), do: other

  defp transition(repo, op, :done),
    do: repo.query!(@complete, [dump(op.id), op.cursor], log: false).num_rows

  defp transition(repo, op, {cursor, _delay}),
    do: repo.query!(@advance, [dump(op.id), op.cursor, cursor], log: false).num_rows

  defp insert!(op, id, cursor, delay) do
    args = %{"version" => 1, "operation_id" => id, "cursor" => cursor}
    Oban.insert!(op.oban, op.worker.new(args, schedule_in: delay))
  end

  defp fail!(repo, op, message) do
    repo.query!(@fail, [dump(op.id), op.cursor, message], log: false)

    Logger.error(
      "release operation #{op.id} (#{op.worker.command_type()}) failed at #{inspect(op.cursor)}; " <>
        "resume with dawarich jobs resume #{op.id}"
    )
  end

  defp dump(id), do: Ecto.UUID.dump!(id)
end
