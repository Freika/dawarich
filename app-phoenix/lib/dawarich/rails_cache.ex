defmodule Dawarich.RailsCache do
  @moduledoc "Interoperate with Rails RedisCacheStore using explicit normalized string keys."
  alias Dawarich.RailsCache.Wire

  @counter "local n=redis.call('INCRBY',KEYS[1],ARGV[1]); if ARGV[2]~='' then redis.call('EXPIRE',KEYS[1],ARGV[2],'NX') end; return n"

  def get(key, opts \\ []) do
    with {:ok, bytes} <- command(["GET", key(key, opts)], opts) do
      cond do
        bytes == nil ->
          :miss

        opts[:raw] ->
          {:ok, bytes}

        true ->
          case entry(bytes, opts) do
            :expired ->
              delete(key, opts)
              :miss

            result ->
              result
          end
      end
    end
  end

  def put(key, value, opts \\ []) do
    now = opts[:now] || System.system_time(:microsecond) / 1_000_000
    expiry = if opts[:expires_in], do: now + opts[:expires_in]

    bytes =
      if opts[:raw],
        do: to_string(value),
        else: Wire.encode(value, expires_at: expiry, version: opts[:version])

    modifiers =
      if opts[:expires_in], do: ["PX", to_string(ceil(opts[:expires_in] * 1000))], else: []

    modifiers = if opts[:unless_exist], do: modifiers ++ ["NX"], else: modifiers

    with {:ok, result} <- command(["SET", key(key, opts), bytes] ++ modifiers, opts),
         do: {:ok, result == "OK"}
  end

  def delete(key, opts \\ []) do
    with {:ok, count} <- command(["UNLINK", key(key, opts)], opts), do: {:ok, count == 1}
  end

  def increment(key, amount \\ 1, opts \\ []) do
    ttl = if opts[:expires_in], do: to_string(trunc(opts[:expires_in])), else: ""
    command(["EVAL", @counter, "1", key(key, opts), to_string(amount), ttl], opts)
  end

  defp entry(bytes, opts) do
    case Wire.decode(bytes) do
      {:ok, entry} ->
        now = opts[:now] || System.system_time(:microsecond) / 1_000_000
        expired = entry.expires_at && entry.expires_at <= now
        mismatch = entry.version && opts[:version] && entry.version != opts[:version]

        cond do
          expired -> :expired
          mismatch -> :miss
          true -> {:ok, entry.value}
        end

      {:error, _} ->
        :miss
    end
  end

  defp key(key, opts) when is_binary(key) and byte_size(key) > 0,
    do: if(opts[:namespace], do: opts[:namespace] <> ":" <> key, else: key)

  defp command(args, opts),
    do: (opts[:command] || (&Dawarich.RailsCache.Connection.command/1)).(args)
end
