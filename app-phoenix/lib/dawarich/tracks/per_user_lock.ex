defmodule Dawarich.Tracks.PerUserLock do
  @moduledoc false

  require Logger

  alias Dawarich.Redis

  @namespace "tracks:per_user_lock"
  @defaults [ttl_ms: 60_000, timeout_ms: 30_000, poll_ms: 100]
  @renew_divisor 3
  @max_renew_errors 3
  @release_lua ~S"""
  if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
  else
    return 0
  end
  """
  @renew_lua ~S"""
  if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("pexpire", KEYS[1], ARGV[2])
  else
    return 0
  end
  """

  def key(user_id), do: "#{@namespace}:#{user_id}"

  def with_user_lock(user_id, fun, opts \\ []) when is_function(fun, 0) do
    opts = with_renew_default(Keyword.merge(@defaults, opts))
    key = key(user_id)
    token = Ecto.UUID.generate()

    case acquire(key, token, System.monotonic_time(:millisecond) + opts[:timeout_ms], opts) do
      :ok ->
        heartbeat = spawn_link(fn -> heartbeat(key, token, opts, 0) end)

        try do
          {:ok, fun.()}
        after
          stop(heartbeat)
          release(key, token)
        end

      error ->
        error
    end
  end

  def renew(key, token, ttl_ms),
    do:
      Redis.command(["EVAL", @renew_lua, "1", key, token, Integer.to_string(ttl_ms)]) == {:ok, 1}

  def release(key, token), do: Redis.command(["EVAL", @release_lua, "1", key, token])

  defp with_renew_default(opts),
    do: Keyword.put_new(opts, :renew_ms, max(div(opts[:ttl_ms], @renew_divisor), opts[:poll_ms]))

  defp acquire(key, token, deadline, opts) do
    case Redis.command(["SET", key, token, "NX", "PX", Integer.to_string(opts[:ttl_ms])]) do
      {:ok, "OK"} -> :ok
      {:ok, nil} -> retry(key, token, deadline, opts)
      {:error, reason} -> {:error, {:redis, reason}}
    end
  end

  defp retry(key, token, deadline, opts) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      Process.sleep(opts[:poll_ms])
      acquire(key, token, deadline, opts)
    end
  end

  defp heartbeat(key, token, opts, errors) do
    receive do
      {:stop, from} -> send(from, {:stopped, self()})
    after
      opts[:renew_ms] ->
        case Redis.command([
               "EVAL",
               @renew_lua,
               "1",
               key,
               token,
               Integer.to_string(opts[:ttl_ms])
             ]) do
          {:ok, 1} ->
            heartbeat(key, token, opts, 0)

          {:ok, _} ->
            lost(key, "renew_lost")

          {:error, _} when errors + 1 >= @max_renew_errors ->
            lost(key, "consecutive_renew_errors")

          {:error, _} ->
            heartbeat(key, token, opts, errors + 1)
        end
    end
  end

  defp lost(key, reason) do
    Logger.warning("event=tracks.per_user_lock_renew_lost key=#{key} reason=#{reason}")

    receive do
      {:stop, from} -> send(from, {:stopped, self()})
    end
  end

  defp stop(pid) do
    send(pid, {:stop, self()})

    receive do
      {:stopped, ^pid} -> :ok
    after
      5_000 ->
        Process.unlink(pid)
        Process.exit(pid, :kill)
        :ok
    end
  end
end
