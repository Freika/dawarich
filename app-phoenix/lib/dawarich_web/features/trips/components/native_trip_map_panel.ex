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
    <div :if={@state in [:path, :plan]} class="relative min-w-0 w-full h-full">
      <DawarichWeb.MapReplay.replay_panel
        :if={@state == :path}
        id={@id <> "-replay"}
        locale={@locale}
        show_day_nav
        native
        hook="native"
      />
      <DawarichWeb.NativeMapHost.map_host
        :if={@state in [:path, :plan]}
        id={@id}
        config={@config}
        locale={@locale}
        hook="Trip"
        class="relative min-w-0 w-full h-full min-h-80 overflow-hidden rounded-lg"
      />
      <p
        :if={@state == :plan}
        data-trip-map-state={@state}
        role="status"
        class="min-w-0 [overflow-wrap:anywhere] p-3"
      >
        <span :if={@state == :plan}>{t(@locale, "trips.show.planned_route", %{})} · </span>
        {t(@locale, "trips.show." <> plan_key(@future), %{})}
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
