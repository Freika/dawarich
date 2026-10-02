defmodule DawarichWeb.PosterStudioSections do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapGalleryCards, only: [poster_card: 1]

  alias DawarichWeb.{Assets, Icon}

  @tokens [
    {"bg", "background"},
    {"water", "water"},
    {"parks", "parks"},
    {"buildings", "buildings"},
    {"railway", "railways"},
    {"boundaries", "boundaries"},
    {"road_motorway", "motorway_roads"},
    {"road_primary", "primary_roads"},
    {"road_residential", "residential_roads"},
    {"road_default", "other_roads"},
    {"route", "track"},
    {"text", "text"}
  ]

  @layers [
    {"roads", "roads", true},
    {"water", "water", true},
    {"landuse", "parks_land_use", true},
    {"buildings", "buildings", false},
    {"rail", "railways", false},
    {"boundaries", "boundaries", false}
  ]

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def poster_sections(assigns) do
    assigns = assign(assigns, tokens: @tokens, layers: @layers)

    ~H"""
    <div class="min-h-0 flex-1 space-y-3 overflow-y-auto p-3">
      <details open class="collapse collapse-arrow bg-base-100 rounded-lg">
        <summary class="collapse-title font-medium min-h-0 cursor-pointer">
          <span class="flex items-center gap-2">
            <Icon.icon name="grid2x2" class="h-4 w-4 opacity-70 shrink-0" />
            {p(@locale, "layout")}
          </span>
        </summary>
        <div class="collapse-content space-y-2">
          <select
            class="select select-bordered select-sm py-0 w-full"
            data-poster-studio-editor-target="layoutSelect"
            data-action="change->poster-studio-editor#layoutChanged"
          ></select>
          <p class="text-xs opacity-60" data-poster-studio-editor-target="layoutDims"></p>
        </div>
      </details>

      <details open class="collapse collapse-arrow bg-base-100 rounded-lg">
        <summary class="collapse-title font-medium min-h-0 cursor-pointer">
          <span class="flex items-center gap-2">
            <Icon.icon name="palette" class="h-4 w-4 opacity-70 shrink-0" />
            {p(@locale, "theme")}
          </span>
        </summary>
        <div class="collapse-content space-y-2">
          <div class="grid grid-cols-6 gap-1.5">
            <button
              :for={theme <- @page.themes}
              type="button"
              class="w-full overflow-hidden rounded-md border border-base-300 ring-primary ring-offset-base-100 transition hover:scale-105 focus:outline-none focus-visible:ring-2"
              style={"height: 32px; background-image: url('#{Assets.stylesheet_path("poster_themes/#{theme.key}.webp")}'); background-size: cover; background-position: center;"}
              title={to_string(theme.name)}
              aria-label={p(@locale, "theme_aria_label", %{theme: theme.name})}
              data-poster-studio-editor-target="swatch"
              data-key={theme.key}
              data-name={to_string(theme.name)}
              data-action="click->poster-studio-editor#pickTheme"
            ></button>
          </div>
          <p class="text-xs opacity-70" data-poster-studio-editor-target="themeLabel"></p>
          <details class="collapse collapse-arrow bg-base-200 rounded-lg">
            <summary class="collapse-title text-sm min-h-0 cursor-pointer select-none">
              {p(@locale, "customize_colors")}
            </summary>
            <div class="collapse-content space-y-1">
              <label :for={{token, label} <- @tokens} class="flex items-center gap-2">
                <input
                  type="color"
                  class="h-7 w-9 cursor-pointer rounded border border-base-300 bg-base-100 p-0.5"
                  data-poster-studio-editor-target="token"
                  data-token={token}
                  data-action="input->poster-studio-editor#tokenChanged"
                />
                <span class="label-text text-sm flex-1">{p(@locale, label)}</span>
                <span
                  class="text-xs opacity-60 tabular-nums"
                  data-poster-studio-editor-target="tokenValue"
                  data-token={token}
                ></span>
              </label>
            </div>
          </details>
        </div>
      </details>

      <details open class="collapse collapse-arrow bg-base-100 rounded-lg">
        <summary class="collapse-title font-medium min-h-0 cursor-pointer">
          <span class="flex items-center gap-2">
            <Icon.icon name="square-pen" class="h-4 w-4 opacity-70 shrink-0" />
            {p(@locale, "text")}
          </span>
        </summary>
        <div class="collapse-content space-y-2">
          <label class="label cursor-pointer justify-start gap-3 py-1">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked
              data-poster-studio-editor-target="textToggle"
              data-action="change->poster-studio-editor#textChanged"
            />
            <span class="label-text text-sm">{p(@locale, "show_text")}</span>
          </label>
          <label class="form-control">
            <span class="label-text text-xs">{p(@locale, "title")}</span>
            <input
              type="text"
              class="input input-bordered input-sm w-full"
              placeholder={p(@locale, "berlin")}
              data-poster-studio-editor-target="titleInput"
              data-action="input->poster-studio-editor#textChanged"
            />
          </label>
          <label class="form-control">
            <span class="label-text text-xs">{p(@locale, "subtitle")}</span>
            <input
              type="text"
              class="input input-bordered input-sm w-full"
              placeholder={p(@locale, "germany")}
              data-poster-studio-editor-target="subtitleInput"
              data-action="input->poster-studio-editor#textChanged"
            />
          </label>
          <label class="label cursor-pointer justify-start gap-3 py-1">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked
              data-poster-studio-editor-target="coordsToggle"
              data-action="change->poster-studio-editor#textChanged"
            />
            <span class="label-text text-sm">{p(@locale, "coordinates_line")}</span>
          </label>
          <label class="form-control">
            <span class="label-text text-xs">{p(@locale, "font")}</span>
            <select
              class="select select-bordered select-sm py-0 w-full"
              data-poster-studio-editor-target="fontSelect"
              data-action="change->poster-studio-editor#fontChanged"
            ></select>
          </label>
        </div>
      </details>

      <details class="collapse collapse-arrow bg-base-100 rounded-lg">
        <summary class="collapse-title font-medium min-h-0 cursor-pointer">
          <span class="flex items-center gap-2">
            <Icon.icon name="layer" class="h-4 w-4 opacity-70 shrink-0" />
            {p(@locale, "layers")}
          </span>
        </summary>
        <div class="collapse-content space-y-1">
          <label
            :for={{key, label, default_on} <- @layers}
            class="label cursor-pointer justify-start gap-3 py-1"
          >
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              data-layer-category={key}
              checked={default_on}
              data-action="change->poster-studio-editor#layersChanged"
            />
            <span class="label-text text-sm">{p(@locale, label)}</span>
          </label>
          <div class="pt-2">
            <div class="flex items-center justify-between py-1">
              <span class="label-text text-xs">{p(@locale, "track_opacity")}</span>
              <span
                class="text-xs font-medium tabular-nums opacity-80"
                data-poster-studio-editor-target="trackOpacityLabel"
              ></span>
            </div>
            <input
              type="range"
              min="10"
              max="100"
              step="5"
              value="100"
              class="range range-primary range-xs"
              data-poster-studio-editor-target="trackOpacity"
              data-action="input->poster-studio-editor#layersChanged"
            />
          </div>
          <div class="pt-2">
            <div class="flex items-center justify-between py-1">
              <span class="label-text text-xs">{p(@locale, "track_width")}</span>
              <span
                class="text-xs font-medium tabular-nums opacity-80"
                data-poster-studio-editor-target="trackWidthLabel"
              ></span>
            </div>
            <input
              type="range"
              min="50"
              max="300"
              step="10"
              value="100"
              class="range range-primary range-xs"
              data-poster-studio-editor-target="trackWidth"
              data-action="input->poster-studio-editor#layersChanged"
            />
          </div>
        </div>
      </details>

      <details class="collapse collapse-arrow bg-base-100 rounded-lg">
        <summary class="collapse-title font-medium min-h-0 cursor-pointer">
          <span class="flex items-center gap-2">
            <Icon.icon name="camera" class="h-4 w-4 opacity-70 shrink-0" />
            {p(@locale, "recent_posters")}
          </span>
        </summary>
        <div class="collapse-content space-y-3">
          <p class="text-xs opacity-60">
            {p(@locale, "server_rendered_posters_from_save_to_gallery_they_stay_here")}
          </p>
          <div id="poster-gallery-list" class="space-y-3">
            <.poster_card :for={poster <- @page.posters} poster={poster} locale={@locale} />
          </div>
        </div>
      </details>
    </div>
    """
  end

  defp p(locale, key, bindings \\ %{}), do: t(locale, "posters.studio." <> key, bindings)
end
