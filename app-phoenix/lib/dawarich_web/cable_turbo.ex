defmodule DawarichWeb.CableTurbo do
  @moduledoc false

  alias DawarichWeb.{NavbarEnd, TripParts}

  def navbar_item(item), do: render(&NavbarEnd.navbar_item/1, %{item: item})
  def badge(count), do: render(&NavbarEnd.badge/1, %{count: count})

  def recalculate_button(trip_id, recalculating, error) do
    render(&TripParts.recalculate_button/1, %{
      trip_id: trip_id,
      recalculating: recalculating,
      error: error,
      locale: "en",
      rails_csrf_token: nil
    })
  end

  defp render(component, assigns),
    do:
      assigns
      |> Map.put(:__changed__, nil)
      |> component.()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
end
