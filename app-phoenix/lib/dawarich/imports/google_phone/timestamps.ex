defmodule Dawarich.Imports.GooglePhone.Timestamps do
  @moduledoc false
  def new, do: %{assigned: %{}, used: MapSet.new()}

  def assign(source, lat, lon, state) do
    key = {source, lat, lon}

    if Map.has_key?(state.assigned, key) do
      {state.assigned[key], state}
    else
      offset =
        Enum.find(0..59, 59, fn offset -> not MapSet.member?(state.used, source + offset) end)

      stamp = source + offset

      {stamp,
       %{
         state
         | assigned: Map.put(state.assigned, key, stamp),
           used: MapSet.put(state.used, stamp)
       }}
    end
  end
end
