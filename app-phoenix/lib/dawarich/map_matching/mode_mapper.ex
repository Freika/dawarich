defmodule Dawarich.MapMatching.ModeMapper do
  @modes %{
    "walking" => "pedestrian",
    "running" => "pedestrian",
    "cycling" => "bicycle",
    "driving" => "auto",
    "bus" => "auto",
    "motorcycle" => "auto"
  }

  def call(mode) when is_atom(mode), do: call(Atom.to_string(mode))
  def call(mode), do: Map.get(@modes, mode)
end
