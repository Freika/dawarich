defmodule Dawarich.State.Lease do
  @moduledoc false

  require Logger

  @defaults [ttl_ms: 60_000, timeout_ms: 30_000, poll_ms: 100, sleep: &Process.sleep/1]
  @max_renew_errors 3
  @acquire """
  INSERT INTO phoenix.leases AS l (name, holder, expires_at)
  VALUES ($1, $2, statement_timestamp() + make_interval(secs => $3))
  ON CONFLICT (name) DO UPDATE SET holder = EXCLUDED.holder, expires_at = EXCLUDED.expires_at
  WHERE l.expires_at <= statement_timestamp()
  """
  @renew """
  UPDATE phoenix.leases SET expires_at = statement_timestamp() + make_interval(secs => $3)
  WHERE name = $1 AND holder = $2 AND expires_at > statement_timestamp()
  """
  @release "DELETE FROM phoenix.leases WHERE name = $1 AND holder = $2"

  def acquire(repo, name, holder, ttl_ms),
    do: changed?(repo, @acquire, [name, holder, ttl_ms / 1000])

  def renew(repo, name, holder, ttl_ms),
    do: changed?(repo, @renew, [name, holder, ttl_ms / 1000])

  def release(repo, name, holder), do: changed?(repo, @release, [name, holder])

  def with_lease(repo, name, fun, opts \\ []) when is_binary(name) and is_function(fun, 0) do
    opts = Keyword.merge(@defaults, opts)
    opts = Keyword.put_new(opts, :renew_ms, max(div(opts[:ttl_ms], 3), opts[:poll_ms]))
    holder = Ecto.UUID.generate()
    deadline = System.monotonic_time(:millisecond) + opts[:timeout_ms]

    if wait(repo, name, holder, deadline, opts) do
      beat = spawn_link(fn -> heartbeat(repo, name, holder, opts, 0) end)

      try do
        {:ok, fun.()}
      after
        Process.unlink(beat)
        Process.exit(beat, :kill)
        quietly(fn -> release(repo, name, holder) end)
      end
    else
      {:error, :timeout}
    end
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
