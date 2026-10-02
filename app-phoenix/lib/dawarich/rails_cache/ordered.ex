defmodule Dawarich.RailsCache.Ordered do
  @moduledoc "Preserve Ruby hash insertion order for source country lookup precedence."
  import Bitwise
  alias Dawarich.RailsCache
  alias Dawarich.RailsCache.{OrderedReader, Value, Wire}

  def get(key, opts \\ []) do
    with {:ok, bytes} when is_binary(bytes) <- RailsCache.get(key, opts ++ [raw: true]),
         {:ok, entry} <- Wire.decode(bytes) do
      now = opts[:now] || System.system_time(:microsecond) / 1_000_000

      cond do
        entry.expires_at && entry.expires_at <= now ->
          RailsCache.delete(key, opts)
          :miss

        entry.version && opts[:version] && entry.version != opts[:version] ->
          :miss

        true ->
          ordered(bytes)
      end
    else
      {:error, _} = error -> error
      _ -> :miss
    end
  end

  def put(key, pairs, opts \\ []),
    do: RailsCache.put(key, %Value{tag: :hash_default, value: {pairs, nil}}, opts)

  defp ordered(<<0, 17, type, _expires::little-float-64, n::little-signed-32, rest::binary>>) do
    <<_version::binary-size(max(n, 0)), payload::binary>> = rest
    payload = if (type &&& 128) != 0, do: :zlib.uncompress(payload), else: payload
    value(OrderedReader.decode(payload))
  end

  defp ordered(<<0, payload::binary>>), do: legacy(payload)
  defp ordered(<<1, payload::binary>>), do: legacy(:zlib.uncompress(payload))
  defp ordered(<<4, 8, _::binary>> = payload), do: value(OrderedReader.decode(payload))

  defp legacy(payload) do
    case OrderedReader.decode(payload) do
      {:ok, [entry | _]} -> value({:ok, entry})
      _ -> :miss
    end
  end

  defp value({:ok, %Value{tag: :hash_default, value: {pairs, nil}}}), do: {:ok, pairs}
  defp value(_), do: :miss
end
