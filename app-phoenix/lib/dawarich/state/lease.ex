defmodule Dawarich.State.Lease do
  @moduledoc false

  require Logger

  @defaults [ttl_ms: 60_000, timeout_ms: 30_000, poll_ms: 100, sleep: &Process.sleep/1]
  @max_renew_errors 3
  @acquire """
  WITH current AS (
    SELECT name, expires_at FROM phoenix.leases WHERE name = $1 FOR UPDATE SKIP LOCKED
  ), taken AS (
    UPDATE phoenix.leases l
    SET holder = $2, expires_at = statement_timestamp() + make_interval(secs => $3)
    FROM current c
    WHERE l.name = c.name AND c.expires_at <= statement_timestamp()
    RETURNING 1
  ), inserted AS (
    INSERT INTO phoenix.leases (name, holder, expires_at)
    SELECT $1, $2, statement_timestamp() + make_interval(secs => $3)
    WHERE NOT EXISTS (SELECT 1 FROM phoenix.leases WHERE name = $1)
    ON CONFLICT (name) DO NOTHING
    RETURNING 1
  )
  SELECT 1 FROM taken UNION ALL SELECT 1 FROM inserted
  """
  @renew """
  UPDATE phoenix.leases SET expires_at = statement_timestamp() + make_interval(secs => $3)
  WHERE name = $1 AND holder = $2 AND expires_at > statement_timestamp()
  """
  @release "DELETE FROM phoenix.leases WHERE name = $1 AND holder = $2"

  def acquire(repo, name, holder, ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0,
    do: changed?(repo, @acquire, [name, holder, ttl_ms / 1000])

  def renew(repo, name, holder, ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0,
    do: changed?(repo, @renew, [name, holder, ttl_ms / 1000])

  def release(repo, name, holder), do: changed?(repo, @release, [name, holder])

  def with_lease(repo, name, fun, opts \\ [])
      when is_binary(name) and (is_function(fun, 0) or is_function(fun, 1)) do
    opts = options!(opts)

    if repo.in_transaction?(),
      do:
        raise(
          ArgumentError,
          "with_lease cannot run inside a transaction: its heartbeat renews on another connection"
        )

    holder = Ecto.UUID.generate()
    deadline = System.monotonic_time(:millisecond) + opts[:timeout_ms]

    if wait(repo, name, holder, deadline, opts) do
      beat = spawn_link(fn -> heartbeat(repo, name, holder, opts, 0) end)

      try do
        {:ok, if(is_function(fun, 1), do: fun.(holder), else: fun.())}
      after
        Process.unlink(beat)
        Process.exit(beat, :kill)
        quietly(fn -> release(repo, name, holder) end)
      end
    else
      {:error, :timeout}
    end
  end

  defp options!(opts) do
    opts = Keyword.merge(@defaults, opts)
    ttl = opts[:ttl_ms]

    unless is_integer(ttl) and ttl > 0,
      do: raise(ArgumentError, "ttl_ms must be a positive integer, got: #{inspect(ttl)}")

    opts = Keyword.put_new(opts, :renew_ms, max(div(ttl, 3), opts[:poll_ms]))
    renew = opts[:renew_ms]

    unless is_integer(renew) and renew > 0 and renew < ttl,
      do:
        raise(
          ArgumentError,
          "renew_ms must be a positive integer below ttl_ms (#{ttl}), got: #{inspect(renew)}"
        )

    opts
  end

  defp wait(repo, name, holder, deadline, opts) do
    cond do
      acquire(repo, name, holder, opts[:ttl_ms]) ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        opts[:sleep].(opts[:poll_ms])
        wait(repo, name, holder, deadline, opts)
    end
  end

  defp heartbeat(repo, name, holder, opts, errors) do
    opts[:sleep].(opts[:renew_ms])

    case quietly(fn -> renew(repo, name, holder, opts[:ttl_ms]) end) do
      true -> heartbeat(repo, name, holder, opts, 0)
      false -> lost(name, "renew_lost")
      :error when errors + 1 >= @max_renew_errors -> lost(name, "consecutive_renew_errors")
      :error -> heartbeat(repo, name, holder, opts, errors + 1)
    end
  end

  defp lost(name, reason),
    do: Logger.warning("event=state.lease_lost name=#{name} reason=#{reason}")

  defp quietly(fun) do
    fun.()
  rescue
    _ in [DBConnection.ConnectionError, Postgrex.Error] -> :error
  end

  defp changed?(repo, sql, params), do: repo.query!(sql, params, log: false).num_rows == 1
end
