defmodule Dawarich.Jsonb do
  @moduledoc false

  def decode(nil), do: nil

  def decode(text) when is_binary(text),
    do: text |> Jason.decode!(objects: :ordered_objects) |> ordered()

  def get({:object, pairs}, key) do
    case List.keyfind(pairs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  def get(_other, _key), do: nil

  defp ordered(%Jason.OrderedObject{values: pairs}),
    do: {:object, Enum.map(pairs, fn {k, v} -> {k, ordered(v)} end)}

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value
end
