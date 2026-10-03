defmodule Dawarich.Imports.SourceDimensions do
  @moduledoc false
  alias Dawarich.Ingest.Sources
  alias Dawarich.Imports.NormalCast
  alias Dawarich.Imports.NormalCast.SymbolicHash
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  @scalars ~w(tracker_id topic ssid bssid)a
  @enums ~w(connection trigger battery_status)a
  @int64 -9_223_372_036_854_775_808..9_223_372_036_854_775_807
  @int64_message """
  Provided value outside of the range of a signed 64bit integer.

  PostgreSQL will treat the column type in question as a numeric.
  This may result in a slow sequential scan due to a comparison
  being performed between an integer or bigint value and a numeric value.

  To allow for this potentially unwanted behavior, set
  ActiveRecord.raise_int_wider_than_64bit to false.
  """
  defdelegate available?(repo), to: Sources
  defdelegate resolve(repo, combo), to: Sources

  def combo(row) do
    enums = Enum.map(@enums, &NormalCast.enum(&1, row[&1]))
    arrays = Enum.map([:inrids, :in_regions], &(array(row, &1) |> NormalCast.json_value()))
    if is_map(row[:tracker_id]), do: pg_error!("42601", ~s(syntax error at or near "::"))
    literals = Enum.map(@scalars, &bound(row[&1]))
    Enum.map(literals, &varchar/1) ++ enums ++ arrays
  end

  defp bound(%SymbolicHash{pairs: pairs}), do: bound_pairs(pairs)
  defp bound(value) when is_map(value), do: bound_pairs(Map.to_list(value))
  defp bound([]), do: :null
  defp bound(values) when is_list(values), do: values |> Enum.map(&literal/1) |> List.last()
  defp bound(value), do: literal(value)

  defp bound_pairs([]), do: :null
  defp bound_pairs(_pairs), do: raise(ArgumentError, "can't quote Array")

  defp literal(nil), do: :null
  defp literal(value) when is_binary(value), do: {:text, value}
  defp literal(value) when is_boolean(value), do: {:text, Atom.to_string(value)}
  defp literal(:infinity), do: {:text, "Infinity"}
  defp literal(:neg_infinity), do: {:text, "-Infinity"}
  defp literal(:nan), do: {:text, "NaN"}
  defp literal(value) when is_integer(value) and value in @int64, do: {:number, "#{value}"}
  defp literal(value) when is_integer(value), do: raise(ArgumentError, @int64_message)
  defp literal(value) when is_float(value), do: {:number, Ruby.to_s(value)}
  defp literal(value) when is_list(value), do: raise(ArgumentError, "can't quote Array")
  defp literal(value) when is_map(value), do: raise(ArgumentError, "can't quote Hash")
  defp literal(value) when is_atom(value), do: {:text, Atom.to_string(value)}

  defp varchar(:null), do: nil
  defp varchar({:text, text}), do: text

  defp varchar({:number, "-" <> _}),
    do:
      pg_error!("42883", "operator does not exist: - character varying",
        hint:
          "No operator matches the given name and argument type. You might need to add an explicit type cast."
      )

  defp varchar({:number, text}), do: text |> Decimal.new() |> Decimal.to_string(:normal)

  defp pg_error!(code, message, fields \\ []) do
    fields = Map.new(fields) |> Map.merge(%{code: code, severity: "ERROR", message: message})
    raise Postgrex.Error, postgres: fields
  end

  defp array(row, key) do
    case Map.fetch(row, key) do
      :error -> []
      {:ok, nil} -> nil
      {:ok, value} when is_list(value) -> value
      {:ok, %SymbolicHash{pairs: pairs}} -> Enum.map(pairs, fn {key, item} -> [key, item] end)
      {:ok, value} when is_map(value) -> Enum.map(value, fn {key, value} -> [key, value] end)
      {:ok, value} -> [value]
    end
  end
end
