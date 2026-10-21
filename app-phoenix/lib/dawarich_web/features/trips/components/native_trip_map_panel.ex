defmodule DawarichWeb.NativeTripMapPanel do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon
  attr :id, :string, default: nil
  attr :config, :map, required: true
  attr :locale, :string, default: "en"

  attr :has_path, :boolean, default: true
  attr :state, :atom, default: :path
  attr :future, :boolean, default: false

  def panel(assigns) do
    assigns = assign(assigns, :id, assigns.id || "native-trip-map-#{assigns.config["tripId"]}")

    ~H"""
    <DawarichWeb.NativeMapHost.map_host
      :if={@state == :path}
      id={@id}
      config={@config}
      locale={@locale}
      hook="Trip"
      loading={false}
      class="w-full h-full rounded-lg overflow-hidden relative"
    >
      <div
        data-native-trip-loading
        class="absolute bottom-4 left-4 z-10 bg-base-100/80 backdrop-blur-sm rounded-lg px-3 py-2 flex items-center gap-2 hidden"
      >
        <span class="loading loading-spinner loading-sm"></span>
        <span class="text-sm">{t(@locale, "trips.show.loading_route_data", %{})}</span>
      </div>
      <DawarichWeb.MapReplay.replay_panel
        id={@id <> "-replay"}
        locale={@locale}
        show_day_nav
        native
        hook="native"
      />
    </DawarichWeb.NativeMapHost.map_host>
    <div :if={@state == :plan} class="relative h-full w-full overflow-hidden rounded-lg">
      <DawarichWeb.NativeMapHost.map_host
        id={@id}
        config={@config}
        locale={@locale}
        hook="Trip"
        loading={false}
        class="h-full w-full"
      />
      <p class="trip-plan-caption" role="status" data-trip-map-state={@state}>
        <Icon.icon name="map" class="size-4 shrink-0" />
        <span class="min-w-0">
          <span class="font-medium">{t(@locale, "trips.show.planned_route", %{})}</span>
          <span class="text-base-content/60"> · {t(@locale, "trips.show." <> plan_key(@future), %{})}</span>
        </span>
      </p>
    </div>
    <div
      :if={@state not in [:path, :plan]}
      class="flex items-center justify-center h-full rounded-lg bg-base-200 p-6"
    >
      <div class="max-w-xs text-center" role="status" data-trip-map-state={@state}>
        <%= cond do %>
          <% @state == :future -> %>
            <Icon.icon name="calendar-clock" class="mx-auto mb-3 size-8 text-base-content/40" />
            <p class="text-base-content/60">
              {t(@locale, "trips.show.trip_has_not_started_yet", %{})}
            </p>
          <% @state == :empty -> %>
            <Icon.icon name="route" class="mx-auto mb-3 size-8 text-base-content/40" />
            <p class="font-medium">{t(@locale, "trips.show.no_locations_recorded", %{})}</p>
            <p class="mt-1 text-sm text-base-content/60">
              {t(@locale, "trips.show.no_locations_recorded_hint", %{})}
            </p>
          <% true -> %>
            <p class="text-base-content/60">
              {t(@locale, "trips.show.trip_path_is_being_calculated", %{})}
            </p>
            <div class="loading loading-spinner loading-lg mt-4"></div>
        <% end %>
      </div>
    </div>
    """
  end

  defp plan_key(true), do: "trip_has_not_started_yet"
  defp plan_key(_), do: "no_locations_recorded"
end
