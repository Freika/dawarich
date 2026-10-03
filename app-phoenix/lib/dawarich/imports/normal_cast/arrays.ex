defmodule Dawarich.Imports.NormalCast.Arrays do
  @moduledoc false
  alias Dawarich.Imports.NormalCast.Text
  def cast(nil), do: nil
  def cast(value) when is_list(value), do: literal(value)

  def cast(value) when is_binary(value),
    do: value |> Dawarich.Imports.NormalCast.ArrayLiteral.decode() |> literal()

  def cast(value), do: Text.cast(value)

  defp literal(values), do: "{" <> Enum.map_join(values, ",", &element/1) <> "}"
  defp element(nil), do: "NULL"
  defp element(values) when is_list(values), do: literal(values)

  defp element(value), do: value |> Text.cast() |> quoted()

  defp quoted(text) do
    if text == "" or String.upcase(text, :ascii) == "NULL" or
         String.contains?(text, ["\"", "\\", "{", "}", ",", " ", "\t", "\n", "\r", "\v", "\f"]),
       do: "\"" <> (text |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")) <> "\"",
       else: text
  end
end
