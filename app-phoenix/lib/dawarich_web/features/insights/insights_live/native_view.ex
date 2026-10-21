defmodule DawarichWeb.InsightsLive.NativeView do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.InsightsLive.{NativeParts, NativeOverviewState, NativeYearCalendar}
  alias DawarichWeb.InsightsParts

  def render(assigns) do
    ~H"""
    <DawarichWeb.InsightsLive.NativeDirect.render :if={@live_action == :details} {assigns} />
    <div :if={@live_action != :details && @data} class="w-full my-5">
      <DawarichWeb.InsightsLive.NativeHeader.render data={@data} locale={@locale} />
      <NativeOverviewState.alert data={@data} locale={@locale} />
      <%= if @data.year_locked do %>
        <NativeOverviewState.locked data={@data} locale={@locale} />
      <% else %>
        <InsightsParts.stats_row
          locale={@locale}
          totals={@data.totals}
          all_time={@data.all_time}
          year={@data.year}
          unit={@data.unit}
        />
        <DawarichWeb.InsightsLive.NativeConsolidated.render data={@data} locale={@locale} />
        <%= if !@data.all_time do %>
          <%= if @data.restricted do %>
            <NativeYearCalendar.render
              data={
                %{
                  year: @data.year,
                  countries: [],
                  daily: [],
                  today: @data.period.today,
                  zone: @data.period.zone
                }
              }
              heatmap={@data.heatmap}
              unit={@data.unit}
              locale={@locale}
            />
          <% else %>
            <%= if @residency && @residency.state != :loading do %>
              <NativeParts.read
                kind="residency"
                read={@residency}
                race={@data.consolidated.race}
                calendar_mode={@calendar_mode}
                calendar_country={@calendar_country}
                heatmap={@data.heatmap}
                unit={@data.unit}
                locale={@locale}
                query={@query}
                path="/insights"
              />
            <% else %>
              <section
                id="insights-residency-loading"
                class="contents"
                role="status"
                aria-live="polite"
              >
                <NativeOverviewState.residency_skeleton />
              </section>
            <% end %>
          <% end %>
          <div
            :if={@data.restricted && @data.consolidated.prior}
            class="mb-6"
            data-testid="distance-race-locked"
          >
            <InsightsParts.locked_card
              locale={@locale}
              title={
                t(@locale, "insights.distance_race.title", %{
                  year: @data.year,
                  previous: @data.year - 1
                })
              }
              badge="#"
              href="#"
              native
            />
          </div>
        <% end %>
        <%= if @details && @details.state not in [:loading, :restricted] do %>
          <NativeParts.read
            kind="details"
            read={@details}
            locale={@locale}
            query={@query}
            path="/insights"
          />
        <% else %>
          <section id="insights-details-loading" class="contents" role="status" aria-live="polite">
            <InsightsParts.details_skeleton />
          </section>
        <% end %>
      <% end %>
      <div class="text-center text-sm text-base-content/50 py-4">
        {t(@locale, "insights.index.geodata_insights_bull_powered_by_your_location_history", %{})}
      </div>
      <DawarichWeb.StatsLive.NativeParts.dialog
        :if={@dialog && @data.all_time}
        dialog={@dialog}
        path="/insights"
        query={@query}
        data={@data.consolidated.index}
        locale={@locale}
      />
      <p
        :if={@refresh_state == :pending || (@details && @details.state == :pending)}
        id="insights-refresh-pending"
        role="status"
        aria-live="polite"
        class="sr-only"
      >
        {t(@locale, "javascript.common.loading", %{})}
      </p>
      <button :if={@refresh_state == :failed} class="btn whitespace-normal" phx-click="retry_refresh">{t(
        @locale,
        "javascript.messages.retry",
        %{}
      )}</button>
    </div>
    """
  end
end
