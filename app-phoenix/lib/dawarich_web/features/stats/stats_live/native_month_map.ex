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
    {first_epoch, last_epoch} = Dawarich.Spatial.CalendarWindow.days(zone, first, last)
    from = first_epoch |> DateTime.from_unix!() |> DateTime.to_iso8601()
    until = last_epoch |> DateTime.from_unix!() |> DateTime.to_iso8601()

    assigns =
      assign(assigns, :config, %{
        "kind" => "owned_stats",
        "interactive" => true,
        "layer" => assigns.layer,
        "range" => %{"startAt" => from, "endAt" => until, "timezone" => zone}
      })

    ~H"""
    <div :if={@data.data.stat} id="stat-page-card" class="card bg-base-100 shadow-xl mb-8">
      <div class="card-body">
        <div class="page-header-row mb-4">
          <h2 class="card-title">
            <DawarichWeb.Icon.icon name="map" class="size-6" /> {t(
              @locale,
              "stats.month.map_summary",
              %{}
            )}
          </h2>
          <div class="flex flex-wrap gap-2">
            <button
              :for={{layer, icon} <- [{"heatmap", "flame"}, {"points", "map-pin"}]}
              phx-click="stats:layer"
              phx-value-layer={layer}
              aria-pressed={to_string(@layer == layer)}
              class={"btn btn-sm btn-outline#{if @layer == layer, do: " btn-active", else: ""}"}
            >
              <DawarichWeb.Icon.icon name={icon} class="size-6" /> {t(
                @locale,
                "stats.month." <> layer,
                %{}
              )}
            </button>
          </div>
        </div>
        <div class="w-full h-96 rounded-lg border border-base-300 relative overflow-hidden">
          <DawarichWeb.NativeMapPreview.preview
            id="monthly-stats-map"
            config={@config}
            locale={@locale}
            class="w-full h-full"
          />
        </div>
      </div>
    </div>
    """
  end
end
