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

  def fetch(key, ttl_ms, fun, opts \\ [])
      when is_integer(ttl_ms) and ttl_ms >= 0 and is_function(fun, 0) do
    case lookup(key) do
      {:ok, value} ->
        value

      :error ->
        # Keep the loader in its caller (including its SQL sandbox context).
        # The lock is released automatically if that caller exits.
        :global.trans({{__MODULE__, key}, self()}, fn -> load(key, ttl_ms, fun, opts) end, [
          node()
        ])
    end
  end

  defp load(key, ttl_ms, fun, opts) do
    case claim(key) do
      {:ok, value} ->
        value

      {:load, token} ->
        try do
          value = fun.()

          unless is_nil(value) and not Keyword.get(opts, :cache_nil, true) do
            now = System.monotonic_time(:millisecond)
            if :ets.info(__MODULE__, :size) > @max, do: evict(now, {key, token, :loading})

            replace(
              {key, token, :loading},
              {key, value, System.monotonic_time(:millisecond) + ttl_ms}
            )
          end

          value
        after
          :ets.delete_object(__MODULE__, {key, token, :loading})
        end
    end
  end

  defp claim(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(__MODULE__, key) do
      [{^key, value, expires_at}] when is_integer(expires_at) and expires_at > now ->
        {:ok, value}

      old ->
        token = make_ref()
        pending = {key, token, :loading}

        claimed =
          case old do
            [] ->
              :ets.insert_new(__MODULE__, pending)

            [entry] ->
              replace(entry, pending) == 1
          end

        if claimed, do: {:load, token}, else: claim(key)
    end
  end

  defp replace({key, previous, expires_at}, {key, value, expires}) do
    :ets.select_replace(__MODULE__, [
      {{:"$1", :"$2", :"$3"},
       [
         {:"=:=", :"$1", {:const, key}},
         {:"=:=", :"$2", {:const, previous}},
         {:"=:=", :"$3", {:const, expires_at}}
       ], [{{:"$1", {:const, value}, {:const, expires}}}]}
    ])
  end

  def lookup(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(__MODULE__, key) do
      [{^key, value, expires_at}] when is_integer(expires_at) and expires_at > now -> {:ok, value}
      _ -> :error
    end
  end

  def put(key, value, ttl_ms) when is_integer(ttl_ms) and ttl_ms >= 0,
    do: store(key, value, ttl_ms)

  def delete({namespace, key} = cache_key) do
    :ets.match_delete(__MODULE__, {{namespace, key, :_}, :_, :_})
    :ets.delete(__MODULE__, cache_key)
    :ok
  end

  def delete(key) do
    :ets.delete(__MODULE__, key)
    :ok
  end

  def delete_digest(namespace, digest) do
    for {cache_key, _, _} <- :ets.tab2list(__MODULE__),
        is_tuple(cache_key),
        tuple_size(cache_key) in [2, 3],
        elem(cache_key, 0) == namespace,
        key = elem(cache_key, 1),
        is_binary(key),
        Base.encode16(:crypto.hash(:sha256, key), case: :lower) == digest,
        do: delete(cache_key)

    :ok
  end

  defp store(key, value, ttl_ms) do
    now = System.monotonic_time(:millisecond)
    if :ets.info(__MODULE__, :size) >= @max, do: evict(now)
    :ets.insert(__MODULE__, {key, value, now + ttl_ms})
    value
  end

  defp evict(now, preserved \\ nil) do
    :ets.select_delete(__MODULE__, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    threshold = if preserved, do: @max + 1, else: @max

    if :ets.info(__MODULE__, :size) >= threshold do
      if preserved do
        :ets.select_delete(__MODULE__, [{:"$1", [{:"=/=", :"$1", {:const, preserved}}], [true]}])
      else
        :ets.delete_all_objects(__MODULE__)
      end
    end
  end
end
