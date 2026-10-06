defmodule Dawarich.MapMatching.Fingerprint do
  alias Dawarich.MapMatching.Input

  def call(%Input{} = input), do: call(Input.fingerprint_payload(input))

  def call(payload) when is_map(payload) do
    :crypto.hash(:sha256, Jason.encode!(ordered(payload))) |> Base.encode16(case: :lower)
  end

  defp ordered(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), ordered(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value
end
