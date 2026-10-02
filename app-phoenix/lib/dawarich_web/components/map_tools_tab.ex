defmodule DawarichWeb.MapToolsTab do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def tools_tab(assigns) do
    ~H"""
    <div class="tab-content" data-tab-content="tools" data-map-panel-target="tabContent">
      <div class="space-y-4">
        <div class="grid grid-cols-2 lg:grid-cols-3 gap-2">
          <button
            type="button"
            class="btn btn-sm btn-outline flex flex-col items-center gap-1 h-auto py-3"
            data-action="click->maps--maplibre#startCreateVisit"
          >
            <Icon.icon name="map-pin-check" class="size-6" />
            <span class="text-xs">{s(@locale, "create_visit")}</span>
          </button>

          <button
            type="button"
            class="btn btn-sm btn-outline flex flex-col items-center gap-1 h-auto py-3"
            data-action="click->maps--maplibre#startCreatePlace"
          >
            <Icon.icon name="map-pin-plus" class="size-6" />
            <span class="text-xs">{s(@locale, "create_place")}</span>
          </button>

          <button
            type="button"
            class="btn btn-sm btn-outline flex flex-col items-center gap-1 h-auto py-3"
            data-maps--maplibre-target="selectAreaButton"
            data-action="click->maps--maplibre#startSelectArea"
          >
            <Icon.icon name="square-dashed-mouse-pointer" class="size-6" />
            <span class="text-xs">{s(@locale, "select_area")}</span>
          </button>

          <button
            type="button"
            class="btn btn-sm btn-outline flex flex-col items-center gap-1 h-auto py-3"
            data-action="click->maps--maplibre#startCreateArea"
          >
            <Icon.icon name="circle-plus" class="size-6" />
            <span class="text-xs">{s(@locale, "create_area")}</span>
          </button>

          <button
            type="button"
            class="btn btn-sm btn-outline flex flex-col items-center gap-1 h-auto py-3"
            data-action="click->maps--maplibre#toggleReplay"
          >
            <Icon.icon name="clock" class="size-6" />
            <span class="text-xs">{s(@locale, "replay")}</span>
          </button>

          <button
            :if={@page.immich and @page.full_access}
            type="button"
            class="btn btn-sm btn-outline flex flex-col items-center gap-1 h-auto py-3"
            id="immich-enrich-toggle-btn"
          >
            <Icon.icon name="camera" class="size-6" />
            <span class="text-xs">{s(@locale, "enrich_photos")}</span>
          </button>
        </div>

        <div
          :if={@page.immich and @page.full_access}
          class="hidden mt-4"
          data-controller="maps--immich-enrich"
          data-maps--immich-enrich-api-key-value={@page.api_key}
          data-maps--immich-enrich-toggle-btn-value="immich-enrich-toggle-btn"
          data-maps--immich-enrich-immich-url-value={to_string(@page.immich_url)}
        >
          <div class="card bg-base-200 shadow-md">
            <div class="card-body p-4">
              <div class="flex justify-between items-center mb-3">
                <h4 class="card-title text-sm gap-2">
                  <Icon.icon name="camera" class="w-4 h-4 text-primary" />
                  {s(@locale, "enrich_photos")}
                </h4>
                <button
                  class="btn btn-ghost btn-xs btn-circle"
                  data-action="click->maps--immich-enrich#toggle"
                  title={s(@locale, "close")}
                >
                  <Icon.icon name="x" class="w-3 h-3" />
                </button>
              </div>

              <div data-maps--immich-enrich-target="scanForm">
                <p class="text-xs text-base-content/60 mb-3">
                  {s(@locale, "match_immich_photos_without_gps_to_your_location_history")}
                </p>
                <div class="space-y-3">
                  <div class="grid grid-cols-2 gap-2">
                    <div class="form-control">
                      <label class="label py-0.5">
                        <span class="label-text text-xs">{s(@locale, "from")}</span>
                      </label>
                      <input
                        type="date"
                        class="input input-bordered input-sm"
                        data-maps--immich-enrich-target="startDate"
                      />
                    </div>
                    <div class="form-control">
                      <label class="label py-0.5">
                        <span class="label-text text-xs">{s(@locale, "to")}</span>
                      </label>
                      <input
                        type="date"
                        class="input input-bordered input-sm"
                        data-maps--immich-enrich-target="endDate"
                      />
                    </div>
                  </div>
                  <div class="form-control">
                    <label class="label py-0.5">
                      <span class="label-text text-xs">{s(@locale, "tolerance_minutes")}</span>
                    </label>
                    <input
                      type="number"
                      value="30"
                      min="1"
                      max="120"
                      class="input input-bordered input-sm"
                      data-maps--immich-enrich-target="tolerance"
                    />
                  </div>
                  <button
                    class="btn btn-primary btn-sm w-full"
                    data-action="click->maps--immich-enrich#scan"
                    data-maps--immich-enrich-target="scanButton"
                  >
                    <Icon.icon name="search" class="w-4 h-4" />
                    {s(@locale, "scan_for_matches")}
                  </button>
                </div>
              </div>

              <div class="hidden text-center py-6" data-maps--immich-enrich-target="loading">
                <span class="loading loading-spinner loading-md text-primary"></span>
                <p
                  class="text-xs text-base-content/60 mt-2"
                  data-maps--immich-enrich-target="loadingText"
                >
                  {s(@locale, "scanning_immich_photos")}
                </p>
              </div>

              <div class="hidden" data-maps--immich-enrich-target="results">
                <div class="flex justify-between items-center mb-2">
                  <div
                    class="text-xs font-medium text-base-content/70"
                    data-maps--immich-enrich-target="resultsSummary"
                  >
                  </div>
                  <label class="label cursor-pointer gap-1.5 py-0">
                    <span class="label-text text-xs">{s(@locale, "all")}</span>
                    <input
                      type="checkbox"
                      class="checkbox checkbox-xs checkbox-primary"
                      checked
                      data-action="change->maps--immich-enrich#toggleSelectAll"
                      data-maps--immich-enrich-target="selectAll"
                    />
                  </label>
                </div>
                <div
                  class="max-h-72 overflow-y-auto space-y-1 -mx-1 px-1"
                  data-maps--immich-enrich-target="matchList"
                >
                </div>
                <div class="divider my-2"></div>
                <div class="flex gap-2">
                  <button
                    class="btn btn-ghost btn-sm flex-1"
                    data-action="click->maps--immich-enrich#backToScan"
                  >
                    <Icon.icon name="arrow-left" class="w-3 h-3" />
                    {s(@locale, "back")}
                  </button>
                  <button
                    class="btn btn-primary btn-sm flex-1"
                    data-action="click->maps--immich-enrich#enrich"
                    data-maps--immich-enrich-target="enrichButton"
                  >
                    {s(@locale, "enrich")}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="hidden mt-4" data-maps--maplibre-target="infoDisplay">
          <div class="card bg-base-200 shadow-md">
            <div class="card-body p-4">
              <div class="flex justify-between items-start mb-2">
                <h4 class="card-title text-base" data-maps--maplibre-target="infoTitle"></h4>
                <button
                  class="btn btn-ghost btn-xs btn-circle"
                  data-action="click->maps--maplibre#closeInfo"
                  title={s(@locale, "close")}
                >
                  ✕
                </button>
              </div>
              <div class="space-y-2 text-sm" data-maps--maplibre-target="infoContent"></div>
              <div class="card-actions justify-end mt-3" data-maps--maplibre-target="infoActions">
              </div>
            </div>
          </div>
        </div>

        <div class="hidden mt-4 space-y-2" data-maps--maplibre-target="selectionActions">
          <%= if @page.full_access do %>
            <button
              type="button"
              class="btn btn-sm btn-outline btn-error btn-block"
              data-action="click->maps--maplibre#deleteSelectedPoints"
              data-maps--maplibre-target="deletePointsButton"
            >
              <Icon.icon name="trash-2" class="size-6" />
              <span data-maps--maplibre-target="deleteButtonText">{s(
                @locale,
                "delete_selected_points"
              )}</span>
            </button>

            <button
              type="button"
              class="hidden btn btn-sm btn-outline btn-warning btn-block"
              data-action="click->maps--maplibre#deleteSelectedAnomalies"
              data-maps--maplibre-target="deleteAnomaliesButton"
            >
              <Icon.icon name="trash-2" class="size-6" />
              <span data-maps--maplibre-target="deleteAnomaliesButtonText">{s(
                @locale,
                "delete_anomaly_points"
              )}</span>
            </button>
          <% end %>

          <div
            class="hidden mt-4 max-h-full overflow-y-auto"
            data-maps--maplibre-target="selectedVisitsContainer"
          >
          </div>

          <div class="hidden" data-maps--maplibre-target="selectedVisitsBulkActions"></div>
        </div>
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
