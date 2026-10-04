defmodule Dawarich.RailsCache.Wire do
  @moduledoc "ActiveSupport::Cache entries: the 7.1 coder and the Marshal 7.0 fallback."
  import Bitwise
  alias Dawarich.RailsCache.{Marshal, Value}

  def decode(bytes, opts \\ []) do
    unpack(bytes, opts)
  rescue
    _ -> {:error, :invalid_cache_entry}
  catch
    _ -> {:error, :invalid_cache_entry}
  end

  def encode(html, expires_at: expires) when is_binary(html) do
    {type, payload} =
      with true <- byte_size(html) >= 1024,
           compressed when byte_size(compressed) < byte_size(html) <- :zlib.compress(html) do
        {2 ||| 128, compressed}
      else
        _ -> {2, html}
      end

    <<0, 17, type, expires * 1.0::little-float-64, -1::little-signed-32, payload::binary>>
  end

  def encode_boolean(value, expires_at: expires) when value in [true, false, nil] do
    tag =
      case value do
        true -> ?T
        false -> ?F
        nil -> ?0
      end

    expires = if is_nil(expires), do: -1.0, else: expires * 1.0
    <<0, 17, 1, expires::little-float-64, -1::little-signed-32, 4, 8, tag>>
  end

  defp unpack(
         <<0, 17, type, expires::little-float-64, length::little-signed-32, rest::binary>>,
         opts
       )
       when length >= -1 do
    <<_version::binary-size(max(length, 0)), payload::binary>> = rest
    payload = if (type &&& 128) != 0, do: :zlib.uncompress(payload), else: payload

    with {:ok, value} <- value(type &&& 127, payload, opts),
         do: {:ok, %{value: value, expires_at: if(expires < 0, do: nil, else: expires)}}
  end

  defp unpack(<<0, payload::binary>>, opts), do: legacy(payload, opts)
  defp unpack(<<1, payload::binary>>, opts), do: legacy(:zlib.uncompress(payload), opts)

  defp unpack(<<4, 8, _::binary>> = payload, opts) do
    with {:ok, value} <- Marshal.decode(payload, opts),
         do: {:ok, %{value: value, expires_at: nil}}
  end

  defp unpack(_, _opts), do: {:error, :unknown_cache_coder}

  defp legacy(payload, opts) do
    case Marshal.decode(payload, opts) do
      {:ok, [value | rest]} when length(rest) <= 2 ->
        {:ok, %{value: value, expires_at: List.first(rest)}}

      {:ok, _} ->
        {:error, :invalid_legacy_entry}

      error ->
        error
    end
  end

  defp value(1, payload, opts), do: Marshal.decode(payload, opts)
  defp value(2, payload, _opts), do: {:ok, payload}

  defp value(3, payload, _opts),
    do: {:ok, %Value{tag: :encoded_string, class: "ASCII-8BIT", value: payload}}

  defp value(4, payload, _opts),
    do: {:ok, %Value{tag: :encoded_string, class: "US-ASCII", value: payload}}

  defp value(_, _, _opts), do: {:error, :unknown_cache_value_type}
end
