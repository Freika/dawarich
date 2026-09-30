defmodule Dawarich.QrCache do
  @moduledoc false

  @max 1_000

  def fetch(payload, fun) do
    key = :crypto.hash(:sha256, payload)
    cache = :persistent_term.get(__MODULE__, %{})

    case cache do
      %{^key => svg} -> svg
      _ -> store(cache, key, fun.())
    end
  end

  defp store(cache, key, svg) do
    cache = if map_size(cache) >= @max, do: %{}, else: cache
    :persistent_term.put(__MODULE__, Map.put(cache, key, svg))
    svg
  end
end
