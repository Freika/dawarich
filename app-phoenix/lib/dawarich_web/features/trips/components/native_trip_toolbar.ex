defmodule DawarichWeb.NativeTripToolbar do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.Icon
  attr :page, :map, required: true
  attr :expanded, :boolean, required: true
  attr :locale, :string, required: true

  def toolbar(assigns) do
    assigns =
      assign(assigns, :layers, [
        {"photos", "camera", "toggle_photo_markers_on_map",
         assigns.page.presentation.settings.photos},
        {"flights", "plane", "toggle_airtrail_flights_on_map",
         assigns.page.presentation.settings.airtrail},
        {"plan", "map", "toggle_plan_on_map", assigns.page.presentation.plan_toggle}
      ])

    ~H"""
    <div class="flex flex-wrap items-center gap-2 mb-4">
      <button
        :for={{layer, icon, title, enabled} <- @layers}
        :if={enabled}
        type="button"
        phx-click="trip:layer"
        phx-value-layer={layer}
        class="btn btn-sm btn-outline gap-1"
        title={s(@locale, title)}
        aria-pressed={if(layer == "plan", do: to_string(@page.config["planEnabled"]))}
      >
        <Icon.icon name={icon} class="w-4 h-4" /><span class="hidden sm:inline">{s(@locale, layer)}</span>
      </button>
      <button
        type="button"
        class="btn btn-sm btn-outline gap-1"
        data-map-replay-open
        title={s(@locale, "replay_the_trip")}
      ><Icon.icon name="play" class="w-4 h-4" /><span class="hidden sm:inline">{s(@locale, "replay")}</span></button>
      <button type="button" class="btn btn-sm btn-outline gap-1" phx-click="trip:days:all"><Icon.icon
        name="chevron-down"
        class="w-4 h-4"
      /><span class="hidden sm:inline">{t(
        @locale,
        if(@expanded, do: "javascript.trip.collapse_all_days", else: "trips.show.show_all_days"),
        %{}
      )}</span></button>
      <%= if @page.presentation.recalculating do %>
        <button class="btn btn-outline btn-sm" disabled><span class="loading loading-spinner loading-xs"></span> {r(
          @locale,
          "recalculating_hellip"
        )}</button>
      <% else %>
        <form
          class="button_to"
          method="post"
          action={"/trips/#{@page.presentation.id}/recalculate"}
          phx-submit="trip:recalculate"
        >
          <button
            class="btn btn-outline btn-sm"
            type="submit"
            data-confirm={r(@locale, "recalculate_this_trip_s_path_distance_and_countries_from_your")}
          ><Icon.icon name="refresh-ccw" class="w-4 h-4" /> {r(@locale, "recalculate")}</button>
          <input type="hidden" name="authenticity_token" value="" />
        </form>
      <% end %>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "trips.show." <> key, %{})
  defp r(locale, key), do: t(locale, "trips.recalculate_button." <> key, %{})
end
