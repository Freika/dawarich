defmodule Dawarich.Imports.NormalCast.ArrayLiteral do
  @moduledoc false

  def decode(text) do
    text = Regex.replace(~r/\A(?:\[-?\d+:-?\d+\])+=/, text, "")

    case array(text) do
      {:ok, values, ""} -> values
      _ -> []
    end
  end

  defp array(<<"{", "}", rest::binary>>), do: {:ok, [], rest}
  defp array(<<"{", rest::binary>>), do: items(rest, [])
  defp array(_), do: :error

  defp items(text, acc) do
    case value(text) do
      {:ok, item, <<",", rest::binary>>} -> items(rest, [item | acc])
      {:ok, item, <<"}", rest::binary>>} -> {:ok, Enum.reverse([item | acc]), rest}
      _ -> :error
    end
  end

  defp value(<<"{", _::binary>> = text), do: array(text)
  defp value(<<"\"", rest::binary>>), do: quoted(rest, [])
  defp value(text), do: bare(text, [])

  defp quoted(<<"\\", byte, rest::binary>>, acc), do: quoted(rest, [byte | acc])
  defp quoted(<<"\"", rest::binary>>, acc), do: {:ok, bytes(acc), rest}
  defp quoted(<<byte, rest::binary>>, acc), do: quoted(rest, [byte | acc])
  defp quoted(_, _), do: :error

  defp bare(<<"\\", byte, rest::binary>>, acc), do: bare(rest, [byte | acc])

  defp bare(<<byte, _::binary>> = rest, acc) when byte in [?,, ?}] do
    token = bytes(acc)
    {:ok, if(token == "NULL", do: nil, else: token), rest}
  end

  defp bare(<<byte, rest::binary>>, acc), do: bare(rest, [byte | acc])
  defp bare(_, _), do: :error
  defp bytes(acc), do: acc |> Enum.reverse() |> :erlang.list_to_binary()
end
