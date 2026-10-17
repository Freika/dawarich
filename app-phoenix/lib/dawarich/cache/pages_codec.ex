defmodule Dawarich.Cache.PagesCodec do
  @moduledoc false
  @limit 1_048_576
  @private ~w(api_key encrypted_password password identity scope user settings sharing_uuid capability token)a
  @structs [Date, DateTime, NaiveDateTime]

  def encode(value) do
    with {:ok, _} <- valid(value, 0, 0),
         bytes <- :erlang.term_to_binary(value),
         true <- byte_size(bytes) <= @limit do
      {:ok, bytes}
    else
      _ -> {:error, :invalid_payload}
    end
  rescue
    _ -> {:error, :invalid_payload}
  end

  def decode(<<131, 80, _::binary>>), do: {:error, :invalid_payload}

  def decode(bytes) when is_binary(bytes) and byte_size(bytes) <= @limit do
    value = :erlang.binary_to_term(bytes, [:safe])
    with {:ok, _} <- valid(value, 0, 0), do: {:ok, value}
  rescue
    _ -> {:error, :invalid_payload}
  end

  def decode(_), do: {:error, :invalid_payload}

  defp valid(_, depth, count) when depth > 32 or count > 65536, do: {:error, :invalid_payload}

  defp valid(value, _, count) when is_binary(value) and byte_size(value) <= 65536,
    do: {:ok, count + 1}

  defp valid(value, _, count) when is_number(value) or is_atom(value), do: {:ok, count + 1}

  defp valid(%{__struct__: type} = value, depth, count) when type in @structs,
    do: valid(Map.from_struct(value), depth + 1, count + 1)

  defp valid(%{__struct__: _}, _, _), do: {:error, :invalid_payload}

  defp valid(value, depth, count) when is_map(value) do
    if Enum.any?(
         Map.keys(value),
         &(&1 in @private or &1 in Enum.map(@private, fn key -> Atom.to_string(key) end))
       ) do
      {:error, :invalid_payload}
    else
      sequence(Enum.flat_map(value, fn {k, v} -> [k, v] end), depth, count)
    end
  end

  defp valid(value, depth, count) when is_tuple(value),
    do: sequence(Tuple.to_list(value), depth, count)

  defp valid(value, depth, count) when is_list(value), do: sequence(value, depth, count)
  defp valid(_, _, _), do: {:error, :invalid_payload}

  defp sequence(values, depth, count) do
    Enum.reduce_while(values, {:ok, count + 1}, fn value, {:ok, count} ->
      case valid(value, depth + 1, count) do
        {:ok, count} -> {:cont, {:ok, count}}
        error -> {:halt, error}
      end
    end)
  end
end
