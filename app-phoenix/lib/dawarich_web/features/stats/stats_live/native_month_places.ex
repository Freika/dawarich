defmodule DawarichWeb.StatsLive.NativeMonthPlaces do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Stats.Toponyms
  alias DawarichWeb.{Icon, StatsFormat}
  attr :locale, :string, required: true
  attr :toponyms, :list, required: true

  def render(assigns) do
    visited = Toponyms.visited(assigns.toponyms)

    assigns =
      assign(assigns,
        visited: visited,
        max: visited |> Enum.map(&length(&1["cities"])) |> Enum.max(fn -> 0 end)
      )

    ~H"""
    <div class="card bg-base-100 shadow-xl mb-8">
      <div class="card-body">
        <h2 class="card-title">
          <Icon.icon name="globe" class="size-6" /> {t(@locale, "stats.month.countries_cities", %{})}
        </h2>
        <div class="space-y-4">
          <%= if @visited != [] do %>
            <div :for={{country, index} <- Enum.with_index(@visited)} class="space-y-2">
              <div class="flex justify-between items-center">
                <span class="font-semibold">{country["country"]}</span>
                <span class="text-sm">
                  {t(@locale, "stats.month.city_count", %{count: length(country["cities"])})}
                  <%= if StatsFormat.city_progress(length(country["cities"]), @max) > 0 do %>
                    ({StatsFormat.city_progress(length(country["cities"]), @max)}%)
                  <% end %>
                </span>
              </div>
              <progress
                class={"progress #{StatsFormat.progress_color(index)} w-full"}
                value={StatsFormat.city_progress(length(country["cities"]), @max)}
                max="100"
              ></progress>
            </div>
          <% else %>
            <div class="text-center text-gray-500">
              <p>{t(@locale, "stats.month.no_location_data_available_for_this_month", %{})}</p>
            </div>
          <% end %>
        </div>
        <div class="divider"></div>
        <div class="flex flex-wrap gap-2">
          <span class="text-sm font-medium">{t(@locale, "stats.month.cities_visited", %{})}</span>
          <%= for country <- @visited, %{"city" => city} <- country["cities"] do %>
            <div class="badge badge-outline">{city}</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
