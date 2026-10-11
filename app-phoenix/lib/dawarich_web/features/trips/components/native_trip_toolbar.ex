defmodule DawarichWeb.NativeTripToolbar do
  @moduledoc false
  use DawarichWeb, :html
  attr :page, :map, required: true
  attr :expanded, :boolean, required: true
  attr :locale, :string, required: true

  def toolbar(assigns) do
    assigns =
      assign(assigns, :layers, [
        {"photos", "photosEnabled", assigns.page.presentation.settings.photos},
        {"flights", "flightsEnabled", assigns.page.presentation.settings.airtrail},
        {"plan", "planEnabled", assigns.page.presentation.plan_toggle}
      ])

    ~H"""
    <div class="flex flex-wrap gap-2 min-w-0 mb-4">
      <button
        :for={{layer, key, enabled} <- @layers}
        :if={enabled}
        type="button"
        phx-click="trip:layer"
        phx-value-layer={layer}
        aria-pressed={to_string(@page.config[key])}
        class="btn btn-sm btn-outline h-auto whitespace-normal"
      >{t(@locale, "trips.show.#{layer}", %{})}</button>
      <button
        type="button"
        phx-click="trip:days:all"
        aria-expanded={to_string(@expanded)}
        class="btn btn-sm btn-outline h-auto whitespace-normal"
      >{t(
        @locale,
        if(@expanded, do: "javascript.trip.collapse_all_days", else: "trips.show.show_all_days"),
        %{}
      )}</button>
    </div>
    """
  end
end
