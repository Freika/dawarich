defmodule DawarichWeb.NativeMapToolsTab do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon

  @tile "btn btn-sm btn-outline flex flex-col items-center gap-1 h-auto py-3"

  attr :locale, :string, required: true
  attr :panel, :string, required: true
  attr :restricted, :boolean, default: false
  attr :page, :map, required: true
  attr :enrichment, :any, default: nil

  def tab(assigns) do
    assigns = assign(assigns, :tile, @tile)

    ~H"""
    <div
      class={["tab-content", @panel == "tools" && "active"]}
      data-tab-content="tools"
    >
      <div class="space-y-4">
        <div class="grid grid-cols-2 lg:grid-cols-3 gap-2">
          <button type="button" class={@tile} data-testid="native-create-visit">
            <Icon.icon name="map-pin-check" class="size-6" />
            <span class="text-xs">{p(@locale, "create_visit")}</span>
          </button>

          <button type="button" class={@tile} data-testid="native-create-place">
            <Icon.icon name="map-pin-plus" class="size-6" />
            <span class="text-xs">{p(@locale, "create_place")}</span>
          </button>

          <button
            type="button"
            class={@tile}
            id="native-select-area"
            data-testid="native-select-area"
            phx-update="ignore"
            data-map-cancel-message={t(@locale, "javascript.visits.cancel_selection", %{})}
            data-map-draw-message={
              t(@locale, "javascript.messages.draw_a_rectangle_on_the_map_to_select_points", %{})
            }
          >
            <Icon.icon name="square-dashed-mouse-pointer" class="size-6" />
            <span class="text-xs">{p(@locale, "select_area")}</span>
          </button>

          <button type="button" class={@tile} data-testid="native-create-area">
            <Icon.icon name="circle-plus" class="size-6" />
            <span class="text-xs">{p(@locale, "create_area")}</span>
          </button>

          <button type="button" class={@tile} data-map-replay-open>
            <Icon.icon name="clock" class="size-6" />
            <span class="text-xs">{p(@locale, "replay")}</span>
          </button>

          <button
            :if={@page.full_access && @page.immich}
            type="button"
            class={@tile}
            id="immich-enrich-toggle-btn"
          >
            <Icon.icon name="camera" class="size-6" />
            <span class="text-xs">{p(@locale, "enrich_photos")}</span>
          </button>
        </div>

        <DawarichWeb.NativeMapEnrichment.tool
          :if={@panel == "tools" && @page.full_access && @page.immich}
          enrichment={@enrichment}
          start_date={String.slice(@page.window.start, 0, 10)}
          end_date={String.slice(@page.window.end, 0, 10)}
          locale={@locale}
        />

        <div id="native-map-info" class="hidden mt-4" data-native-info-display phx-update="ignore">
          <div class="card bg-base-200 shadow-md">
            <div class="card-body p-4">
              <div class="flex justify-between items-start mb-2">
                <h4 class="card-title text-base" data-native-info-title></h4>
                <button
                  class="btn btn-ghost btn-xs btn-circle"
                  title={p(@locale, "close")}
                  data-native-info-close
                >✕</button>
              </div>
              <div class="space-y-2 text-sm" data-native-info-content></div>
              <div class="card-actions justify-end mt-3" data-native-info-actions></div>
            </div>
          </div>
        </div>

        <div
          id="native-map-selection"
          class="hidden mt-4 space-y-2"
          data-map-selection
          phx-update="ignore"
        >
          <button
            :if={!@restricted}
            type="button"
            class="btn btn-sm btn-outline btn-error btn-block"
            data-map-delete-points
          >
            <Icon.icon name="trash-2" class="size-6" />
            <span data-map-delete-points-text>{p(@locale, "delete_selected_points")}</span>
          </button>

          <button
            :if={!@restricted}
            type="button"
            class="hidden btn btn-sm btn-outline btn-warning btn-block"
            data-map-delete-anomalies
          >
            <Icon.icon name="trash-2" class="size-6" />
            <span data-map-delete-anomalies-text>{p(@locale, "delete_anomaly_points")}</span>
          </button>

          <div class="hidden mt-4 max-h-full overflow-y-auto" data-map-selected-visits></div>

          <div class="hidden" data-map-selected-bulk></div>
        </div>
      </div>
    </div>
    """
  end

  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
