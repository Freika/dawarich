defmodule DawarichWeb.TripFormat do
  @moduledoc false

  def distance(nil, _factor), do: 0
  def distance(meters, factor), do: round(meters / factor)
end
