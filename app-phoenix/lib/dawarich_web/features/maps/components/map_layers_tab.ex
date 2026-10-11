defmodule DawarichWeb.MapLayersTab do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapParts, only: [pro_badge: 1]
  import DawarichWeb.MapLayersPlaces, only: [places_layers: 1]

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :timeline, :boolean, required: true

  def layers_tab(assigns) do
    ~H"""
    <div
      class={"tab-content#{unless @timeline, do: " active"}"}
      data-tab-content="layers"
      data-map-panel-target="tabContent"
    >
      <div class="space-y-4">
        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              data-maps--maplibre-target="pointsToggle"
              data-action="change->maps--maplibre#togglePoints"
            />
            <span class="label-text font-medium">{s(@locale, "points")}</span>
          </label>
          <p class="text-sm text-base-content/60 ml-14">
            {s(@locale, "show_individual_location_points")}
          </p>

          <div class="ml-14 mt-3 space-y-3">
            <div>
              <label class="label cursor-pointer justify-start gap-3 py-0">
                <input
                  type="checkbox"
                  class="toggle toggle-primary toggle-sm"
                  data-maps--maplibre-target="pointsEditToggle"
                  data-action="change->maps--maplibre#togglePointsEditing"
                />
                <span class="label-text">{s(@locale, "edit_points")}</span>
              </label>
              <%= if !@page.full_access do %>
                <p class="text-sm text-base-content/60 ml-10 mt-1">
                  {s(@locale, "allow_dragging_points_to_correct_their_position")}
                </p>
                <p class="text-xs text-warning ml-10 mt-1">
                  {s(@locale, "editing_points_is_a_pro_feature_this_stays_on_for")}
                </p>
              <% else %>
                <p class="text-sm text-base-content/60 ml-10 mt-1">
                  {s(
                    @locale,
                    "allow_dragging_points_to_correct_their_position_remembered_across_sessio"
                  )}
                </p>
              <% end %>
              <p
                class="text-xs text-warning ml-10 mt-1 hidden"
                data-maps--maplibre-target="pointsEditUnavailableNote"
              >
              </p>
            </div>
          </div>
        </div>

        <div class="divider"></div>

        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-warning"
              data-maps--maplibre-target="anomaliesToggle"
              data-action="change->maps--maplibre#toggleAnomalies"
            />
            <span class="label-text font-medium">{s(@locale, "anomalies")}</span>
          </label>
          <p class="text-sm text-base-content/60 ml-14">
            {s(@locale, "show_filtered_gps_noise_points")}
          </p>
        </div>

        <div class="divider"></div>

        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              data-maps--maplibre-target="tracksToggle"
              data-action="change->maps--maplibre#toggleTracks"
            />
            <span class="label-text font-medium">{s(@locale, "tracks")}</span>
          </label>
          <p class="text-sm text-base-content/60 ml-14">
            {s(@locale, "show_backend_calculated_tracks")}
          </p>
        </div>

        <div :if={@page.airtrail} class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              data-maps--maplibre-target="flightsToggle"
              data-action="change->maps--maplibre#toggleFlights"
            />
            <span class="label-text font-medium">{s(@locale, "flights")}</span>
          </label>
          <p class="text-sm text-base-content/60 ml-14">
            {s(@locale, "show_airtrail_flights_as_arcs_hides_overlapping_gps")}
          </p>
        </div>

        <div class="divider"></div>

        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              data-maps--maplibre-target="heatmapToggle"
              data-action="change->maps--maplibre#toggleHeatmap"
            />
            <span class="label-text font-medium">{s(@locale, "heatmap")}</span>
            <.pro_badge restricted={!@page.full_access} url={@page.badge_url} locale={@locale} />
          </label>
          <p class="text-sm text-base-content/60 ml-14">{s(@locale, "show_density_heatmap")}</p>
        </div>

        <div class="divider"></div>

        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              data-testid="hexagons-toggle"
              data-maps--maplibre-target="hexagonsToggle"
              data-action="change->maps--maplibre#toggleHexagons"
            />
            <span class="label-text font-medium">{s(@locale, "hexagons")}</span>
            <.pro_badge restricted={!@page.full_access} url={@page.badge_url} locale={@locale} />
          </label>
          <p class="text-sm text-base-content/60 ml-14">
            {s(@locale, "show_point_density_as_hexagonal_cells")}
          </p>
        </div>

        <div class="divider"></div>

        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              data-maps--maplibre-target="visitsToggle"
              data-action="change->maps--maplibre#toggleVisits"
            />
            <span class="label-text font-medium">{s(@locale, "visits")}</span>
          </label>
          <p class="text-sm text-base-content/60 ml-14">{s(@locale, "show_detected_area_visits")}</p>
        </div>

        <div class="ml-14 space-y-2" data-maps--maplibre-target="visitsSearch" style="display: none;">
          <input
            type="text"
            id="visits-search"
            placeholder={s(@locale, "filter_by_name")}
            class="input input-sm input-bordered w-full"
            data-action="input->maps--maplibre#searchVisits"
          />

          <select
            class="select select-bordered w-full"
            data-action="change->maps--maplibre#filterVisits"
          >
            <option value="all">{s(@locale, "all_visits")}</option>
            <option value="confirmed">{s(@locale, "confirmed_only")}</option>
            <option value="suggested">{s(@locale, "suggested_only")}</option>
          </select>
        </div>

        <div class="divider"></div>

        <.places_layers page={@page} locale={@locale} />
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
