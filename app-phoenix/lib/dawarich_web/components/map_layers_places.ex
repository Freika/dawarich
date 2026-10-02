defmodule DawarichWeb.MapLayersPlaces do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapParts, only: [pro_badge: 1]

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def places_layers(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          data-maps--maplibre-target="placesToggle"
          data-action="change->maps--maplibre#togglePlaces"
        />
        <span class="label-text font-medium">{s(@locale, "places")}</span>
      </label>
      <p class="text-sm text-base-content/60 ml-14">{s(@locale, "show_your_saved_places")}</p>
    </div>

    <div class="ml-14 space-y-2" data-maps--maplibre-target="placesFilters" style="display: none;">
      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input
            type="checkbox"
            class="toggle toggle-sm"
            data-maps--maplibre-target="enableAllPlaceTagsToggle"
            data-action="change->maps--maplibre#toggleAllPlaceTags"
          />
          <span class="label-text text-sm">{s(@locale, "enable_all_tags")}</span>
        </label>
      </div>
      <div class="form-control">
        <label class="label">
          <span class="label-text text-sm">{s(@locale, "filter_by_tags")}</span>
        </label>
        <div class="flex flex-wrap gap-2">
          <label class="cursor-pointer">
            <input
              type="checkbox"
              name="place_tag_ids[]"
              value="untagged"
              class="checkbox checkbox-xs hidden peer"
              data-action="change->maps--maplibre#filterPlacesByTags"
            />
            <span
              class="badge badge-sm badge-outline transition-all peer-checked:scale-105"
              style="border-color: #94a3b8; color: #94a3b8;"
              data-checked-style="background-color: #94a3b8; color: white;"
            >
              {s(@locale, "untagged")}
            </span>
          </label>

          <label :for={tag <- @page.tags} class="cursor-pointer">
            <input
              type="checkbox"
              name="place_tag_ids[]"
              value={to_string(tag.id)}
              class="checkbox checkbox-xs hidden peer"
              data-action="change->maps--maplibre#filterPlacesByTags"
            />
            <span
              class="badge badge-sm badge-outline transition-all peer-checked:scale-105"
              style={"border-color: #{tag.color}; color: #{tag.color};"}
              data-checked-style={"background-color: #{tag.color}; color: white;"}
            >
              {tag.icon} #{tag.name}
            </span>
          </label>
        </div>
        <label class="label">
          <span class="label-text-alt">{s(@locale, "click_tags_to_filter_places")}</span>
        </label>
      </div>
    </div>

    <div class="divider"></div>

    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          data-maps--maplibre-target="photosToggle"
          data-action="change->maps--maplibre#togglePhotos"
        />
        <span class="label-text font-medium">{s(@locale, "photos")}</span>
      </label>
      <p class="text-sm text-base-content/60 ml-14">{s(@locale, "show_geotagged_photos")}</p>
    </div>

    <div class="divider"></div>

    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          data-maps--maplibre-target="areasToggle"
          data-action="change->maps--maplibre#toggleAreas"
        />
        <span class="label-text font-medium">{s(@locale, "areas")}</span>
      </label>
      <p class="text-sm text-base-content/60 ml-14">{s(@locale, "show_defined_areas")}</p>
    </div>

    <div class="divider"></div>

    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          data-maps--maplibre-target="fogToggle"
          data-action="change->maps--maplibre#toggleFog"
        />
        <span class="label-text font-medium">{s(@locale, "fog_of_war")}</span>
        <.pro_badge restricted={!@page.full_access} url={@page.badge_url} locale={@locale} />
      </label>
      <p class="text-sm text-base-content/60 ml-14">{s(@locale, "show_explored_areas")}</p>
      <div class="flex gap-4 ml-14 mt-1">
        <label class="label cursor-pointer gap-2 py-0">
          <input
            type="radio"
            name="fogOfWarMode"
            value="points"
            class="radio radio-sm"
            checked={@page.fog_mode == "points"}
            data-action="change->maps--maplibre#updateFogMode"
          />
          <span class="label-text text-sm">{s(@locale, "per_point")}</span>
        </label>
        <label class="label cursor-pointer gap-2 py-0">
          <input
            type="radio"
            name="fogOfWarMode"
            value="hexagons"
            class="radio radio-sm"
            checked={@page.fog_mode == "hexagons"}
            data-action="change->maps--maplibre#updateFogMode"
          />
          <span class="label-text text-sm">{s(@locale, "per_hexagon")}</span>
        </label>
      </div>
    </div>

    <div class="divider"></div>

    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          data-maps--maplibre-target="scratchToggle"
          data-action="change->maps--maplibre#toggleScratch"
        />
        <span class="label-text font-medium">{s(@locale, "scratch_map")}</span>
        <.pro_badge restricted={!@page.full_access} url={@page.badge_url} locale={@locale} />
      </label>
      <p class="text-sm text-base-content/60 ml-14">{s(@locale, "show_scratched_countries")}</p>
    </div>

    <%= if @page.family do %>
      <div class="divider"></div>

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-3">
          <input
            type="checkbox"
            class="toggle toggle-primary"
            data-maps--maplibre-target="familyToggle"
            data-action="change->maps--maplibre#toggleFamily"
          />
          <span class="label-text font-medium">{s(@locale, "family_members")}</span>
        </label>
        <p class="text-sm text-base-content/60 ml-14">{s(@locale, "show_family_member_locations")}</p>
      </div>

      <div
        class="ml-14 space-y-2"
        data-maps--maplibre-target="familyMembersList"
        style="display: none;"
      >
        <div class="text-xs text-base-content/60 mb-2">
          {s(@locale, "click_to_center_on_member")}
        </div>
        <div data-maps--maplibre-target="familyMembersContainer" class="space-y-1"></div>
      </div>
    <% end %>
    """
  end

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
