defmodule DawarichWeb.InsightsLive.NativeView do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.InsightsLive.NativeParts

  def render(assigns) do
    ~H"""
    <DawarichWeb.InsightsLive.NativeDirect.render :if={@live_action == :details} {assigns} />
    <main :if={@live_action != :details} class="w-full min-w-0 my-5">
      <h1 class="text-3xl font-bold break-words">{@page_title}</h1>
      <NativeParts.overview
        :if={@data}
        data={@data}
        query={@query}
        locale={@locale}
        path={if(@live_action == :details, do: "/insights/details", else: "/insights")}
      />
      <p
        :if={@data && (@data.year_locked || @data.restricted)}
        id="insights-locked"
        role="status"
        class="alert flex-wrap min-w-0 break-words"
      >
        {t(@locale, "stats.locked_year_card.available_on_pro", %{})}
      </p>
      <button
        :if={@data && @data.restricted}
        id="insights-upgrade"
        class="btn whitespace-normal"
        phx-click="upgrade"
      >{t(@locale, "shared.plan_data_window_alert.upgrade_to_pro", %{})}</button>
      <NativeParts.read
        :if={@details}
        kind="details"
        read={@details}
        locale={@locale}
        query={@query}
        path={if(@live_action == :details, do: "/insights/details", else: "/insights")}
      />
      <NativeParts.read
        :if={@residency}
        calendar_mode={@calendar_mode}
        calendar_country={@calendar_country}
        heatmap={@data && @data[:heatmap]}
        unit={if @data, do: @data.unit, else: "km"}
        kind="residency"
        read={@residency}
        locale={@locale}
        query={@query}
        path={if(@live_action == :details, do: "/insights/details", else: "/insights")}
      />
      <DawarichWeb.StatsLive.NativeParts.dialog
        :if={@dialog && @data && @data.all_time}
        dialog={@dialog}
        path="/insights"
        query={@query}
        data={@data.consolidated.index}
        locale={@locale}
      />
      <button :if={@data && !@data.year_locked} id="insights-update" class="btn" phx-click="update">{t(
        @locale,
        "stats.index.update_stats",
        %{}
      )}</button>
      <p
        :if={@refresh_state == :pending || (@details && @details.state == :pending)}
        id="insights-refresh-pending"
        role="status"
        aria-live="polite"
      >
        {t(@locale, "javascript.common.loading", %{})}
      </p>
      <button :if={@refresh_state == :failed} class="btn whitespace-normal" phx-click="retry_refresh">{t(
        @locale,
        "javascript.messages.retry",
        %{}
      )}</button>
    </main>
    """
  end
end
