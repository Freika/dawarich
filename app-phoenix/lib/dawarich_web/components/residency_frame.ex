defmodule DawarichWeb.ResidencyFrame do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.{LocalTime, Residency}
  alias Dawarich.Insights.Heatmap
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{Icon, LocalizedDate}

  @colors ~w(bg-blue-600 bg-orange-700 bg-emerald-600 bg-fuchsia-600 bg-amber-700 bg-cyan-700 bg-rose-600 bg-violet-500 bg-lime-700 bg-pink-600 bg-teal-600 bg-yellow-700 bg-indigo-500 bg-red-600)

  def data(user, year, now) do
    settings = user.settings || %{}
    {_zone, today} = LocalTime.local(settings, now)

    with {:ok, window} <- Residency.local_window(user.id, year, settings, today),
         {:ok, {:object, pairs}} <- Residency.term(user.id, window) do
      result = Map.new(pairs)
      {:object, daily} = result["daily_countries"]
      countries = for {:object, fields} <- result["countries"], do: country(Map.new(fields))

      {:ok,
       %{
         year: result["year"],
         days_in_year: result["days_in_year"],
         total: result["total_tracked_days"],
         countries: countries,
         daily: Map.new(daily),
         today: today,
         colors: countries |> Enum.with_index() |> Map.new(fn {c, i} -> {c.name, color(i)} end),
         weeks: Heatmap.weeks(result["year"])
       }}
    end
  end

  defp country(fields) do
    %{
      name: fields["country_name"],
      iso: fields["iso_a2"],
      days: fields["days"],
      year_percentage: fields["year_percentage"],
      warning: fields["threshold_warning"],
      periods:
        for {:object, period} <- fields["periods"] do
          period = Map.new(period)

          %{
            first: Date.from_iso8601!(period["start_date"]),
            last: Date.from_iso8601!(period["end_date"]),
            days: period["consecutive_days"]
          }
        end
    }
  end

  attr :year, :integer, required: true
  attr :days_in_year, :integer, required: true
  attr :total, :integer, required: true
  attr :countries, :list, required: true
  attr :colors, :map, required: true
  attr :daily, :map, required: true
  attr :weeks, :list, required: true
  attr :today, Date, required: true
  attr :locale, :string, required: true

  def frame(assigns) do
    assigns = assign(assigns, labels: labels(assigns.weeks, assigns.year, assigns.locale))

    ~H"""
    <turbo-frame id="residency-content">
      <%= if @countries != [] do %>
        <div class="flex flex-col lg:flex-row gap-6">
          <div class="w-full lg:w-1/4 mb-6">
            <div
              class="card bg-base-200 h-full lg:max-h-64 overflow-hidden"
              data-testid="residency-country-card"
            >
              <div class="card-body p-3 min-h-0">
                <div class="flex items-center gap-2 mb-2">
                  <Icon.icon name="globe" class="w-4 h-4 text-base-content/60" />
                  <h3 class="text-base font-semibold">{s(@locale, "countries")}</h3>
                </div>
                <div
                  class="space-y-0.5 flex-1 min-h-0 lg:overflow-y-auto lg:pr-1"
                  data-testid="residency-country-list"
                >
                  <details
                    :for={{country, index} <- Enum.with_index(@countries)}
                    class="group bg-base-100 rounded-lg"
                  >
                    <summary class="flex items-center gap-2 px-3 py-2 cursor-pointer list-none select-none [&::-webkit-details-marker]:hidden">
                      <div class={"flex-shrink-0 w-2.5 h-2.5 rounded-full #{color(index)}"}></div>
                      <div class="flex-shrink-0 w-6 h-4 rounded-sm overflow-hidden shadow-sm">
                        <%= if Ruby.present?(country.iso) do %>
                          <Icon.flag
                            code={String.downcase(country.iso)}
                            class="w-full h-full object-cover"
                          />
                        <% else %>
                          <Icon.icon name="globe" class="w-4 h-4 opacity-40" />
                        <% end %>
                      </div>
                      <span class="font-medium flex-1 text-sm truncate">
                        {country.name}
                        <Icon.icon
                          :if={country.warning}
                          name="triangle-alert"
                          class="w-3.5 h-3.5 inline text-warning ml-1"
                        />
                      </span>
                      <div class="text-right flex-shrink-0">
                        <span class="font-mono font-semibold text-sm">{country.days}</span>
                        <span class="text-xs opacity-40 ml-0.5">({Ruby.to_s(country.year_percentage)}%)</span>
                      </div>
                      <Icon.icon
                        name="chevron-down"
                        class="w-4 h-4 flex-shrink-0 opacity-40 transition-transform group-open:rotate-180"
                      />
                    </summary>
                    <div class="px-3 pb-2">
                      <div class="border-t border-base-300 pt-2 space-y-1.5">
                        <p class="text-[10px] font-medium opacity-40 uppercase tracking-wider">
                          {s(@locale, "stay_periods")}
                        </p>
                        <div
                          :for={period <- country.periods}
                          class="flex items-center justify-between gap-2 text-xs"
                        >
                          <span>
                            {LocalizedDate.l(@locale, period.first, "short_month_day")} – {LocalizedDate.l(
                              @locale,
                              period.last,
                              "medium"
                            )}
                          </span>
                          <span class="font-mono bg-base-300 px-1.5 py-0.5 rounded flex-shrink-0">
                            {period.days} {s(@locale, "days")}
                          </span>
                        </div>
                      </div>
                    </div>
                  </details>
                </div>
                <div
                  :if={Enum.any?(@countries, & &1.warning)}
                  class="flex items-start gap-2 mt-2 text-xs opacity-50"
                >
                  <Icon.icon
                    name="triangle-alert"
                    class="w-3.5 h-3.5 text-warning flex-shrink-0 mt-0.5"
                  />
                  <span>{s(@locale, "exceeds_183_day_threshold_common_in_many_tax_jurisdictions")}</span>
                </div>
              </div>
            </div>
          </div>
          <div class="w-full lg:w-3/4 mb-6">
            <div class="card bg-base-200 h-full">
              <div class="card-body p-4">
                <div class="flex justify-between items-center mb-1">
                  <div class="flex items-center gap-2">
                    <Icon.icon name="calendar-range" class="w-5 h-5 text-base-content/60" />
                    <h3 class="text-lg font-semibold">{s(@locale, "days_per_country")}</h3>
                  </div>
                  <div class="badge badge-ghost">{@total} / {@days_in_year} {s(@locale, "days")}</div>
                </div>
                <p class="text-xs opacity-50 mb-4">
                  {s(@locale, "distinct_days_with_at_least_one_tracked_point_per_country")}
                </p>
                <div class="overflow-x-auto">
                  <div class="min-w-fit relative">
                    <div class="flex ml-8 mb-1">
                      <div
                        :for={{name, margin} <- @labels}
                        style={"margin-left: #{margin}px"}
                        class="text-xs text-base-content/60"
                      >
                        {name}
                      </div>
                    </div>
                    <div class="flex">
                      <div
                        class="flex flex-col justify-around mr-2 text-xs text-base-content/60"
                        style="height: 98px;"
                      >
                        <span>{s(@locale, "mon")}</span>
                        <span>{s(@locale, "wed")}</span>
                        <span>{s(@locale, "fri")}</span>
                      </div>
                      <div class="flex gap-0.5">
                        <div :for={week <- @weeks} class="flex flex-col gap-0.5">
                          <.cell
                            :for={offset <- 0..6}
                            date={Date.add(week, offset)}
                            year={@year}
                            today={@today}
                            daily={@daily}
                            colors={@colors}
                            locale={@locale}
                          />
                        </div>
                      </div>
                    </div>
                    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 mt-3 text-xs text-base-content/60">
                      <div
                        :for={{country, index} <- Enum.with_index(Enum.take(@countries, 7))}
                        class="flex items-center gap-1"
                      >
                        <div class={"w-2.5 h-2.5 rounded-sm #{color(index)}"}></div>
                        <span>{country.name}</span>
                      </div>
                      <span :if={length(@countries) > 7} class="opacity-40">+{length(@countries) - 7} {s(
                        @locale,
                        "more"
                      )}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200 mb-6">
          <div class="card-body p-6 items-center text-center opacity-50">
            <Icon.icon name="globe" class="w-10 h-10 mb-2" />
            <p class="text-sm">{s(@locale, "no_country_data_for")} {@year}.</p>
            <p class="text-xs">{s(@locale, "points_need_reverse_geocoding_to_detect_countries")}</p>
          </div>
        </div>
      <% end %>
    </turbo-frame>
    """
  end

  attr :date, Date, required: true
  attr :year, :integer, required: true
  attr :today, Date, required: true
  attr :daily, :map, required: true
  attr :colors, :map, required: true
  attr :locale, :string, required: true

  def cell(assigns) do
    in_year = assigns.date.year == assigns.year
    future = Date.compare(assigns.date, assigns.today) == :gt
    country = Map.get(assigns.daily, Date.to_iso8601(assigns.date))

    assigns =
      assign(assigns,
        in_year: in_year,
        future: future,
        country: country,
        color: country && assigns.colors[country]
      )

    ~H"""
    <%= cond do %>
      <% @in_year and not @future and @color != nil -> %>
        <div
          class={"w-3 h-3 rounded-sm cursor-pointer transition-opacity hover:opacity-80 hover:z-50 tooltip tooltip-top #{@color}"}
          data-tip={"#{@country} — #{LocalizedDate.l(@locale, @date, "short_weekday_month_day")}"}
        >
        </div>
      <% @in_year and not @future -> %>
        <div class="w-3 h-3 rounded-sm bg-base-300"></div>
      <% true -> %>
        <div class={"w-3 h-3 rounded-sm #{if @future and @in_year, do: "bg-base-300/30", else: ""}"}>
        </div>
    <% end %>
    """
  end

  defp labels(weeks, year, locale) do
    {labels, _last} =
      weeks
      |> Heatmap.month_labels(year, locale)
      |> Enum.map_reduce(0, fn %{index: index, name: name}, last ->
        {{name, (index - last) * 14}, index + 1}
      end)

    labels
  end

  defp color(index), do: Enum.at(@colors, rem(index, length(@colors)))
  defp s(locale, key), do: t(locale, "map.residency.show." <> key, %{})
end
