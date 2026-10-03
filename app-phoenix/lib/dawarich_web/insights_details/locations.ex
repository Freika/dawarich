defmodule DawarichWeb.InsightsDetails.Locations do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.Icon
  alias DawarichWeb.InsightsDetails.Format

  def render(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-5">
        <h2 class="card-title text-lg flex items-center gap-2">
          <Icon.icon name="map-pin" class="w-5 h-5 text-primary" /> {tr(
            @locale,
            "top_visited_locations"
          )}
        </h2>
        <%= if @data.top_visits != [] do %>
          <div class="space-y-3 mt-3">
            <div
              :for={{location, index} <- Enum.with_index(@data.top_visits)}
              class="p-3 bg-base-300 rounded-lg"
            >
              <div class="flex justify-between items-center mb-2">
                <div class="flex items-center gap-2">
                  <span class="w-6 h-6 bg-primary text-primary-content rounded-full flex items-center justify-center text-xs font-bold">{index +
                    1}</span>
                  <span class="font-medium">{location.name}</span>
                </div>
              </div>
              <div class="grid grid-cols-2 gap-2 text-center">
                <div>
                  <div class="text-xl font-bold">{location.visit_count}</div><div class="text-xs text-base-content/60">
                    {tr(@locale, "visit_count", %{count: location.visit_count})}
                  </div>
                </div>
                <div>
                  <div class="text-xl font-bold">
                    {Format.location_time(@locale, location.total_duration)}
                  </div><div class="text-xs text-base-content/60">{tr(@locale, "total_time")}</div>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="text-center py-8 text-base-content/60">
            <div class="flex flex-col items-center gap-2">
              <Icon.icon name="map-pin" class="w-8 h-8 opacity-50" /><p>
                {tr(@locale, "no_visit_data_available_for_this_period")}
              </p><p class="text-sm">{tr(@locale, "confirmed_visits_will_appear_here")}</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp tr(locale, key, bindings \\ %{}),
    do: Format.translation(locale, "location_clusters", key, bindings)
end
