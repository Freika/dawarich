defmodule DawarichWeb.InsightsLive.NativeCountryRibbon do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.{LocalizedDate, InsightsLive.NativeCalendarData}
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    assigns =
      assign(assigns,
        colors: NativeCalendarData.colors(assigns.data.countries),
        lanes: Enum.take(assigns.data.countries, 8),
        days: Date.day_of_year(Date.new!(assigns.data.year, 12, 31))
      )

    ~H"""
    <section
      class="card bg-base-200 mb-6"
      data-testid="country-ribbon"
      aria-labelledby="country-ribbon-title"
    >
      <div class="card-body p-5 gap-4">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 id="country-ribbon-title" class="flex items-center gap-2 text-xl font-bold min-w-0">
            <.icon name="globe" class="w-5 h-5 text-base-content/60 shrink-0" /> {t(
              @locale,
              "insights.country_ribbon.title",
              %{year: @data.year}
            )}
          </h2>
          <span class="badge badge-ghost tabular-nums">{@data.total} / {@days} {t(
            @locale,
            "map.residency.show.days",
            %{}
          )}</span>
        </div>
        <div class="overflow-x-auto">
          <div class="grid min-w-[30rem] grid-cols-[7rem_minmax(0,1fr)] items-center gap-x-3 gap-y-1.5">
            <%= for country <- @lanes do %>
              <div class="flex min-w-0 items-center gap-2 text-sm">
                <span
                  class="h-2.5 w-2.5 shrink-0 rounded-full"
                  style={"background: #{@colors[country.name]}"}
                ></span>
                <span class="min-w-0 truncate">{country.name}</span>
                <span class="ml-auto shrink-0 tabular-nums text-base-content/50">{country.days}</span>
              </div>
              <div class="country-ribbon__lane" data-testid="country-ribbon-lane">
                <span
                  :for={{first, last} <- country.periods}
                  class="country-ribbon__segment"
                  tabindex="0"
                  role="img"
                  aria-label={label(@locale, country.name, first, last)}
                  title={label(@locale, country.name, first, last)}
                  style={style(first, last, @days, @colors[country.name])}
                ></span>
                <span
                  :if={@data.year == @data.today.year}
                  class="country-ribbon__today"
                  style={"left: #{Dawarich.RubyFloat.round((Date.day_of_year(@data.today) - 1) / @days * 100, 3)}%"}
                  title={t(@locale, "insights.country_ribbon.today", %{})}
                ></span>
              </div>
            <% end %>
            <div></div>
            <div class="grid grid-cols-12 text-xs text-base-content/60">
              <span :for={month <- 1..12}>{LocalizedDate.l(
                @locale,
                Date.new!(@data.year, month, 1),
                "abbreviated_month_name"
              )}</span>
            </div>
          </div>
        </div>
        <p :if={@data.country_count > length(@lanes)} class="text-xs text-base-content/60">
          {t(@locale, "insights.country_ribbon.more_countries", %{
            count: @data.country_count - length(@lanes)
          })}
        </p>
      </div>
    </section>
    """
  end

  defp label(locale, country, first, last),
    do:
      t(locale, "insights.country_ribbon.segment", %{
        country: country,
        from: LocalizedDate.l(locale, first, "short_month_day"),
        to: LocalizedDate.l(locale, last, "short_month_day"),
        count: Date.diff(last, first) + 1
      })

  defp style(first, last, days, color),
    do:
      "left: #{Dawarich.RubyFloat.round((Date.day_of_year(first) - 1) / days * 100, 3)}%; width: #{Dawarich.RubyFloat.round(max((Date.diff(last, first) + 1) / days * 100, 0.4), 3)}%; background: #{color}"
end
