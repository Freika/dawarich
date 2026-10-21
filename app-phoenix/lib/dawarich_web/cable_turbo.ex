defmodule DawarichWeb.CableTurbo do
  @moduledoc false
  defdelegate navbar_item(item), to: Dawarich.Cable.HTML
  defdelegate badge(count), to: Dawarich.Cable.HTML
  defdelegate recalculate_button(trip_id, recalculating, error), to: Dawarich.Cable.HTML
end
