defmodule DawarichWeb.InsightsLive.NativeOverviewState do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.InsightsParts
  attr :locale, :string, required: true
  attr :data, :map, required: true

  def alert(assigns) do
    ~H"""
    <div
      :if={@data.restricted}
      id="native-insights-window-alert"
      role="alert"
      class="alert alert-info shadow-lg my-4 !flex !flex-row !items-center justify-between gap-4"
    >
      <div class="flex items-center gap-2 min-w-0">
        <.icon name="info" class="flex-shrink-0" />
        <span>{t(
          @locale,
          "shared.plan_data_window_alert.your_lite_plan_includes_the_last_12_months_of_data",
          %{}
        )}</span>
      </div>
      <div class="flex items-center gap-2 flex-shrink-0">
        <a
          id="insights-upgrade"
          href="#"
          phx-click="upgrade"
          class="btn btn-sm btn-primary"
          target="_blank"
          rel="noopener"
        >{t(@locale, "shared.plan_data_window_alert.upgrade_to_pro", %{})}</a>
        <button
          type="button"
          phx-click={Phoenix.LiveView.JS.hide(to: "#native-insights-window-alert")}
          class="btn btn-sm btn-circle btn-ghost"
          aria-label={t(@locale, "shared.plan_data_window_alert.close", %{})}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          ><path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M6 18L18 6M6 6l12 12"
          /></svg>
        </button>
      </div>
    </div>
    """
  end

  def residency_skeleton(assigns) do
    ~H"""
    <div class="mb-6"><InsightsParts.skeleton_card lines={6} /></div>
    <div class="mb-6 grid gap-6 lg:grid-cols-2">
      <InsightsParts.skeleton_card :for={_ <- 1..2} lines={3} />
    </div>
    """
  end

  def locked(assigns) do
    ~H"""
    <section
      id="insights-locked"
      role="status"
      class="contents [&_.tooltip:before]:left-auto [&_.tooltip:before]:right-0 [&_.tooltip:before]:translate-x-0"
    >
      <div class="grid grid-cols-1 sm:grid-cols-4 gap-4 mb-6">
        <.card
          :for={name <- ~w(total_distance countries cities days_traveling)}
          locale={@locale}
          name={name}
        />
      </div>
      <div class="flex flex-col lg:flex-row gap-6">
        <div class="w-full lg:w-3/4 mb-6"><.card locale={@locale} name="activity_heatmap" /></div>
        <div class="w-full lg:w-1/4 mb-6"><.card locale={@locale} name="activity_streak" /></div>
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6 mt-6">
        <div class="space-y-6">
          <.card
            :for={name <- ~w(year_comparison activity_breakdown location_clusters)}
            locale={@locale}
            name={name}
          />
        </div>
        <div class="space-y-6">
          <.card :for={name <- ~w(monthly_digest travel_patterns)} locale={@locale} name={name} />
        </div>
      </div>
      <.card locale={@locale} name="movement_wellness" />
    </section>
    """
  end

  attr :locale, :string, required: true
  attr :name, :string, required: true

  def card(assigns) do
    ~H"""
    <InsightsParts.locked_card
      locale={@locale}
      title={t(@locale, "insights.index." <> @name, %{})}
      badge="#"
      href="#"
      native
    />
    """
  end
end
