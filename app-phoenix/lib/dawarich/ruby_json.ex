defmodule Dawarich.RubyJson do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  def encode_to_iodata!(term), do: term |> floats(&RubyFloat.json/1) |> Jason.encode_to_iodata!()
  def encode_exact!(term), do: term |> floats(&RubyFloat.to_s/1) |> Jason.encode!()
  defdelegate decode!(text), to: Jason

  defp floats(value, format) when is_float(value), do: Jason.Fragment.new(format.(value))
  defp floats(list, format) when is_list(list), do: Enum.map(list, &floats(&1, format))

  defp floats(%Jason.OrderedObject{values: pairs} = object, format),
    do: %{object | values: Enum.map(pairs, fn {k, v} -> {k, floats(v, format)} end)}

  defp floats(%_{} = struct, _format), do: struct

  defp floats(map, format) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, floats(v, format)} end)

  defp floats(other, _format), do: other
end
