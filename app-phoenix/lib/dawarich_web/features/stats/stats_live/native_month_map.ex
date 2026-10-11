defmodule DawarichWeb.StatsLive.NativeMonthMap do
  @moduledoc false
  use DawarichWeb, :html
  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :layer, :string, default: "heatmap"

  def render(assigns) do
    first = Date.new!(assigns.data.year, assigns.data.month, 1)
    last = Date.end_of_month(first)
    zone = assigns.data.period.zone
    {from, _} = Dawarich.LocalTime.day_bounds(zone, first)
    {_, until} = Dawarich.LocalTime.day_bounds(zone, last)

    assigns =
      assign(assigns, :config, %{
        "kind" => "owned_stats",
        "interactive" => true,
        "layer" => assigns.layer,
        "range" => %{"startAt" => from, "endAt" => until, "timezone" => zone}
      })

    ~H"""
    <section :if={@data.data.stat} class="min-w-0 my-4">
      <h2>{t(@locale, "stats.month.map_summary", %{})}</h2>
      <div class="flex flex-wrap gap-2 min-w-0 mb-3">
        <button
          :for={layer <- ~w(heatmap points)}
          phx-click="stats:layer"
          phx-value-layer={layer}
          aria-pressed={to_string(@layer == layer)}
          class="btn btn-sm whitespace-normal"
        >
          {t(@locale, "stats.month." <> layer, %{})}
        </button>
      </div>
      <DawarichWeb.NativeMapPreview.preview
        id="monthly-stats-map"
        config={@config}
        locale={@locale}
        class="h-96 w-full min-w-0 bg-base-200 rounded-lg"
      />
    </section>
    """
  end
end
