defmodule Dawarich.TtlCache do
  @moduledoc false

  @max 10_000

  def create_table,
    do:
      :ets.new(__MODULE__, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

  def fetch(key, ttl_ms, fun) when is_integer(ttl_ms) and ttl_ms >= 0 and is_function(fun, 0) do
    case lookup(key) do
      {:ok, value} -> value
      :error -> store(key, fun.(), ttl_ms)
    end
  end

  def lookup(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(__MODULE__, key) do
      [{^key, value, expires_at}] when expires_at > now -> {:ok, value}
      _ -> :error
    end
  end

  def put(key, value, ttl_ms) when is_integer(ttl_ms) and ttl_ms >= 0,
    do: store(key, value, ttl_ms)

  def delete(key) do
    :ets.delete(__MODULE__, key)
    :ok
  end

  defp store(key, value, ttl_ms) do
    now = System.monotonic_time(:millisecond)
    if :ets.info(__MODULE__, :size) >= @max, do: evict(now)
    :ets.insert(__MODULE__, {key, value, now + ttl_ms})
    value
  end

  defp evict(now) do
    :ets.select_delete(__MODULE__, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    if :ets.info(__MODULE__, :size) >= @max, do: :ets.delete_all_objects(__MODULE__)
  end
end
