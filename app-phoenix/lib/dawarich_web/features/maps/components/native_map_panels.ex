defmodule DawarichWeb.NativeMapPanels do
  @moduledoc false

  @layers ~w(Points Tracks Heatmap Hexagons) ++
            ["Scratch map", "Photos", "Visits", "Places", "Areas", "Family Members"]

  def layers, do: ["Fog of War" | @layers]
end
