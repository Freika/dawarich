defmodule Dawarich.RailsCache.Wire do
  @moduledoc "ActiveSupport cache coder7.1 and its actual Marshal7.0 fallback."
  import Bitwise
  alias Dawarich.RailsCache.{Marshal, Value}

  def decode(bytes) do
    unpack(bytes)
  rescue
    _ -> {:error, :invalid_cache_entry}
  catch
    _ -> {:error, :invalid_cache_entry}
  end

  def encode(value, opts \\ []) do
    version = opts[:version]
    expires = opts[:expires_at] || -1.0

    {type, payload} =
      case value do
        %Value{tag: :encoded_string, class: "ASCII-8BIT", value: bytes} -> {3, bytes}
        %Value{tag: :encoded_string, class: "US-ASCII", value: bytes} -> {4, bytes}
        bytes when is_binary(bytes) -> {2, bytes}
        value -> {1, Marshal.encode(value)}
      end

    {type, payload} = compress(type, payload, opts[:compress_threshold] || 1024)
    version_bytes = version || ""
    length = if version, do: byte_size(version_bytes), else: -1

    <<0, 17, type, expires * 1.0::little-float-64, length::little-signed-32,
      version_bytes::binary, payload::binary>>
  end

  defp unpack(<<0, 17, type, expires::little-float-64, length::little-signed-32, rest::binary>>)
       when length >= -1 do
    <<version::binary-size(max(length, 0)), payload::binary>> = rest
    payload = if (type &&& 128) != 0, do: :zlib.uncompress(payload), else: payload

    with {:ok, value} <- value(type &&& 127, payload),
         {:ok, version} <- version(if(length < 0, do: nil, else: version)) do
      {:ok,
       %{value: value, expires_at: if(expires < 0, do: nil, else: expires), version: version}}
    end
  end

  defp unpack(<<0, payload::binary>>), do: legacy(payload)
  defp unpack(<<1, payload::binary>>), do: legacy(:zlib.uncompress(payload))

  defp unpack(<<4, 8, _::binary>> = payload) do
    with {:ok, value} <- Marshal.decode(payload),
         do: {:ok, %{value: value, expires_at: nil, version: nil}}
  end

  defp unpack(_), do: {:error, :unknown_cache_coder}

  defp legacy(payload) do
    with {:ok, packed} <- Marshal.decode(payload) do
      case packed do
        [value] -> {:ok, %{value: value, expires_at: nil, version: nil}}
        [value, expires] -> {:ok, %{value: value, expires_at: expires, version: nil}}
        [value, expires, version] -> {:ok, %{value: value, expires_at: expires, version: version}}
        _ -> {:error, :invalid_legacy_entry}
      end
    end
  end

  defp value(1, payload), do: Marshal.decode(payload)
  defp value(2, payload), do: {:ok, payload}

  defp value(3, payload),
    do: {:ok, %Value{tag: :encoded_string, class: "ASCII-8BIT", value: payload}}

  defp value(4, payload),
    do: {:ok, %Value{tag: :encoded_string, class: "US-ASCII", value: payload}}

  defp value(_, _), do: {:error, :unknown_cache_value_type}
  defp version(<<4, 8, _::binary>> = bytes), do: Marshal.decode(bytes)
  defp version(value), do: {:ok, value}

  defp compress(type, payload, threshold) when byte_size(payload) >= threshold do
    compressed = :zlib.compress(payload)

    if byte_size(compressed) < byte_size(payload),
      do: {type ||| 128, compressed},
      else: {type, payload}
  end

  defp compress(type, payload, _), do: {type, payload}
end
