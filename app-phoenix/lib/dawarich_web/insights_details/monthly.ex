defmodule DawarichWeb.InsightsDetails.Monthly do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.{Digests}
  alias DawarichWeb.{Chartkick, Icon, LocalizedDate}
  alias DawarichWeb.InsightsDetails.{Format, MonthFormat}

  def render(assigns) do
    data = assigns.data
    digest = data.monthly

    assigns =
      assign(assigns,
        digest: digest,
        locations: if(digest, do: MonthFormat.top_locations(data), else: []),
        first: if(digest, do: digest["first_time_visits"] || %{}, else: %{}),
        change: if(digest, do: (digest["year_over_year"] || %{})["distance_change_percent"]),
        countries_change: if(digest, do: (digest["year_over_year"] || %{})["countries_change"])
      )

    ~H"""
    <%= if @digest do %>
      <div class="card bg-base-200">
        <div class="card-body p-5">
          <div class="flex justify-between items-center">
            <h2 class="card-title text-lg flex items-center gap-2">
              <Icon.icon name="calendar" class="w-5 h-5 text-primary" /> {MonthFormat.title(
                @locale,
                @digest
              )}
            </h2>
            <div class="join">
              <%= if link = MonthFormat.adjacent(@data.year, @data.selected_month, @data.available_months, -1) do %>
                <a class="join-item btn btn-xs btn-ghost" href={link}><Icon.icon
                  name="chevron-left"
                  class="w-4 h-4"
                /></a>
              <% else %>
                <button class="join-item btn btn-xs btn-ghost btn-disabled"><Icon.icon
                  name="chevron-left"
                  class="w-4 h-4"
                /></button>
              <% end %>
              <div class="dropdown dropdown-end">
                <label tabindex="0" class="join-item btn btn-xs btn-ghost">{MonthFormat.month(
                  @locale,
                  @digest
                )} <Icon.icon name="chevron-down" class="w-3 h-3 ml-1" /></label>
                <ul
                  tabindex="0"
                  class="dropdown-content z-[1] menu p-2 shadow bg-base-200 rounded-box w-40"
                >
                  <li :for={month <- @data.available_months}>
                    <a
                      class={if(month == @data.selected_month, do: "active", else: "")}
                      href={MonthFormat.path(@data.year, month)}
                    >{LocalizedDate.month_name(@locale, @data.year, month)}</a>
                  </li>
                </ul>
              </div>
              <%= if link = MonthFormat.adjacent(@data.year, @data.selected_month, @data.available_months, 1) do %>
                <a class="join-item btn btn-xs btn-ghost" href={link}><Icon.icon
                  name="chevron-right"
                  class="w-4 h-4"
                /></a>
              <% else %>
                <button class="join-item btn btn-xs btn-ghost btn-disabled"><Icon.icon
                  name="chevron-right"
                  class="w-4 h-4"
                /></button>
              <% end %>
            </div>
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-4 [&_.text-xs]:break-words [&>div]:min-w-0">
            <div
              :for={{icon, value, title} <- metrics(@locale, @digest, @data.unit)}
              class="text-center"
            >
              <div class="flex items-center justify-center gap-1 text-base-content/60 text-xs mb-1">
                <Icon.icon name={icon} class="w-3 h-3" />
              </div>
              <div class="font-bold">{value}</div><div class="text-xs text-base-content/60">
                {tr(@locale, title)}
              </div>
            </div>
          </div>
          <div class="mt-4">
            <div class="text-sm font-medium mb-2">{tr(@locale, "weekly_pattern")}</div><div class="h-32">
              <Chartkick.column_chart
                id="chart-1"
                height="120px"
                data={MonthFormat.chart(@locale, @digest, @data.unit)}
                options={[
                  suffix: " " <> @data.unit,
                  colors: ["#3abff8"],
                  library: [
                    plugins: [legend: [display: false]],
                    scales: [
                      x: [grid: [display: false]],
                      y: [grid: [color: "rgba(0,0,0,0.1)"], ticks: [display: false]]
                    ]
                  ]
                ]}
              />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4 mt-4">
            <div>
              <div class="text-sm font-medium mb-2">{tr(@locale, "top_locations")}</div><div class="space-y-1 text-sm">
                <%= if @locations != [] do %>
                  <div
                    :for={{location, index} <- Enum.with_index(@locations)}
                    class="flex justify-between"
                  >
                    <span>{index + 1}. {location.name}</span><span class="text-info">{Format.location_time(
                      @locale,
                      location.minutes
                    )}</span>
                  </div>
                <% else %>
                  <div class="text-base-content/50">{tr(@locale, "no_location_data")}</div>
                <% end %>
              </div>
            </div>
            <div>
              <div class="flex items-center gap-1 text-sm font-medium mb-2">
                <Icon.icon name="flag" class="w-4 h-4 text-success" /> {tr(@locale, "first_visits")}
              </div><div class="space-y-1 text-sm">
                <%= if (@first["countries"] || []) != [] or (@first["cities"] || []) != [] do %>
                  <div
                    :for={country <- Enum.take(@first["countries"] || [], 2)}
                    class="flex justify-between"
                  >
                    <span class="text-success">{country}</span><span class="badge badge-success badge-xs">{tr(
                      @locale,
                      "country"
                    )}</span>
                  </div>
                  <div
                    :for={
                      city <-
                        Enum.take(
                          @first["cities"] || [],
                          3 - length(Enum.take(@first["countries"] || [], 2))
                        )
                    }
                    class="flex justify-between"
                  >
                    <span class="text-success">{city}</span><span class="badge badge-info badge-xs">{tr(
                      @locale,
                      "city"
                    )}</span>
                  </div>
                <% else %>
                  <div class="text-base-content/50">{tr(@locale, "no_new_places_this_month")}</div>
                <% end %>
              </div>
            </div>
          </div>
          <div :if={@change not in [nil, false]} class="mt-4 pt-4 border-t border-base-300">
            <div class="text-sm font-medium text-base-content/60 mb-2">
              {tr(@locale, "vs_previous_month")}
            </div>
            <div class="flex gap-4 text-sm">
              <div class="flex items-center gap-1">
                <span class={"badge badge-#{Format.color(@change)} badge-sm"}>{Format.signed(@change)}%</span><span class="text-base-content/60">{tr(
                  @locale,
                  "distance"
                )}</span>
              </div>
              <div :if={@countries_change not in [nil, false, 0]} class="flex items-center gap-1">
                <span class={"badge badge-#{Format.color(@countries_change)} badge-sm"}>{Format.signed(
                  @countries_change
                )}</span><span class="text-base-content/60">{tr(@locale, "countries_2")}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% else %>
      <div :if={@data.available_months != []} class="card bg-base-200">
        <div class="card-body p-5">
          <h2 class="card-title text-lg flex items-center gap-2">
            <Icon.icon name="calendar" class="w-5 h-5 text-primary" /> {tr(@locale, "monthly_digest")}
          </h2>
          <p class="text-base-content/60">{tr(@locale, "select_a_month_to_view_its_digest")}</p>
          <div class="flex flex-wrap gap-2 mt-2">
            <a
              :for={month <- @data.available_months}
              class="btn btn-sm btn-outline"
              href={MonthFormat.path(@data.year, month)}
            >{LocalizedDate.month_name(@locale, @data.year, month)}</a>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp tr(locale, key), do: Format.translation(locale, "monthly_digest", key)

  defp metrics(locale, digest, unit),
    do: [
      {"route", MonthFormat.distance(locale, digest, unit), "total_distance"},
      {"calendar", MonthFormat.active_days(digest), "active_days"},
      {"globe", Digests.countries_count(digest["toponyms"] || []), "countries"},
      {"building", Digests.cities_count(digest["toponyms"] || []), "cities"}
    ]
end
