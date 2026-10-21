defmodule DawarichWeb.InsightsLive.NativeDirect do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{InsightsParts, InsightsLive.NativeParts}

  def render(assigns) do
    ~H"""
    <div id="native-insights-details" class="w-full">
      <section :if={@data && @data.restricted} id="insights-locked" role="status" class="contents">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          <div class="space-y-6">
            <.locked
              :for={name <- ~w(year_comparison activity_breakdown location_clusters)}
              name={name}
              locale={@locale}
            />
          </div>
          <div class="space-y-6">
            <.locked :for={name <- ~w(monthly_digest travel_patterns)} name={name} locale={@locale} />
          </div>
        </div>
        <.locked name="movement_wellness" locale={@locale} />
      </section>
      <NativeParts.read
        :if={@data && !@data.restricted}
        kind="details"
        read={@details || %{state: :loading}}
        locale={@locale}
        query={@query}
        path="/insights/details"
      />
    </div>
    """
  end

  defp locked(assigns) do
    ~H"""
    <InsightsParts.locked_card
      locale={@locale}
      title={t(@locale, "insights.details." <> @name, %{})}
      badge="#"
      href="#"
      native
    />
    """
  end
end
