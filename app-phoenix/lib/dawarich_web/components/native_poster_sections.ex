defmodule DawarichWeb.NativePosterSections do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.{Assets, Icon}

  @layouts [
    {"print",
     ~w(print-a5 print-a4 print-a3 print-a2 print-a1 print-a0 print-30x40 print-50x70 print-70x100 print-letter print-a4-landscape print-a3-landscape)},
    {"social",
     ~w(social-ig-square social-ig-portrait social-story social-x-header social-youtube-thumb)},
    {"wallpaper",
     ~w(wallpaper-fhd wallpaper-4k wallpaper-ultrawide wallpaper-phone wallpaper-tablet)}
  ]

  @fonts [
    {"inter", "Inter", "Poster Inter"},
    {"oswald", "Oswald", "Poster Oswald"},
    {"playfair-display", "Playfair Display", "Poster Playfair Display"},
    {"jetbrains-mono", "JetBrains Mono", "Poster JetBrains Mono"}
  ]

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

  attr :themes, :list, required: true
  attr :locale, :string, required: true

  def poster_sections(assigns) do
    assigns =
      assign(assigns, layouts: @layouts, fonts: @fonts, tokens: @tokens, layers: @layers)

    ~H"""
    <.section icon="grid2x2" title={p(@locale, "layout")} open>
      <select class="select select-bordered select-sm w-full py-0" data-poster-layout>
        <optgroup :for={{category, ids} <- @layouts} label={js(@locale, "categories." <> category)}>
          <option :for={id <- ids} value={id} selected={id == "print-a3"}>
            {js(@locale, "layouts." <> id)}
          </option>
        </optgroup>
      </select>
      <p class="text-xs opacity-60" data-poster-layout-dims></p>
    </.section>

    <.section icon="palette" title={p(@locale, "theme")} open>
      <div class="grid grid-cols-6 gap-1.5">
        <button
          :for={theme <- @themes}
          type="button"
          class="w-full overflow-hidden rounded-md border border-base-300 ring-primary ring-offset-base-100 transition hover:scale-105 focus:outline-none focus-visible:ring-2"
          style={"height: 32px; background-image: url('#{Assets.stylesheet_path("poster_themes/#{theme.key}.webp")}'); background-size: cover; background-position: center;"}
          title={to_string(theme.name)}
          aria-label={p(@locale, "theme_aria_label", %{theme: theme.name})}
          aria-pressed="false"
          data-poster-swatch
          data-key={theme.key}
          data-name={to_string(theme.name)}
        ></button>
      </div>
      <p class="text-xs opacity-70" data-poster-theme-label></p>
      <details class="collapse collapse-arrow rounded-lg bg-base-200">
        <summary class="collapse-title min-h-0 cursor-pointer select-none text-sm">
          {p(@locale, "customize_colors")}
        </summary>
        <div class="collapse-content space-y-1">
          <label :for={{token, label} <- @tokens} class="flex items-center gap-2">
            <input
              type="color"
              class="h-7 w-9 cursor-pointer rounded border border-base-300 bg-base-100 p-0.5"
              data-poster-token={token}
            />
            <span class="label-text min-w-0 flex-1 text-sm">{p(@locale, label)}</span>
            <span class="text-xs tabular-nums opacity-60" data-poster-token-value={token}></span>
          </label>
        </div>
      </details>
    </.section>

    <.section icon="square-pen" title={p(@locale, "text")} open>
      <label class="label cursor-pointer justify-start gap-3 py-1">
        <input
          type="checkbox"
          class="toggle toggle-sm toggle-primary"
          checked
          data-poster-text-toggle
        />
        <span class="label-text text-sm">{p(@locale, "show_text")}</span>
      </label>
      <label class="form-control">
        <span class="label-text text-xs">{p(@locale, "title")}</span>
        <input
          type="text"
          class="input input-bordered input-sm w-full"
          placeholder={p(@locale, "berlin")}
          data-poster-title
        />
      </label>
      <label class="form-control">
        <span class="label-text text-xs">{p(@locale, "subtitle")}</span>
        <input
          type="text"
          class="input input-bordered input-sm w-full"
          placeholder={p(@locale, "germany")}
          data-poster-subtitle
        />
      </label>
      <label class="label cursor-pointer justify-start gap-3 py-1">
        <input type="checkbox" class="toggle toggle-sm toggle-primary" checked data-poster-coords />
        <span class="label-text text-sm">{p(@locale, "coordinates_line")}</span>
      </label>
      <label class="form-control">
        <span class="label-text text-xs">{p(@locale, "font")}</span>
        <select class="select select-bordered select-sm w-full py-0" data-poster-font>
          <option
            :for={{key, label, family} <- @fonts}
            value={key}
            selected={key == "oswald"}
            style={"font-family: \"#{family}\", sans-serif"}
          >
            {label}
          </option>
        </select>
      </label>
    </.section>

    <.section icon="layer" title={p(@locale, "layers")}>
      <label :for={{key, label, on} <- @layers} class="label cursor-pointer justify-start gap-3 py-1">
        <input
          type="checkbox"
          class="toggle toggle-sm toggle-primary"
          checked={on}
          data-poster-layer={key}
        />
        <span class="label-text text-sm">{p(@locale, label)}</span>
      </label>
      <.range name="opacity" label={p(@locale, "track_opacity")} min="10" max="100" step="5" />
      <.range name="width" label={p(@locale, "track_width")} min="50" max="300" step="10" />
    </.section>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :open, :boolean, default: false
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <details open={@open} class="collapse collapse-arrow rounded-lg bg-base-100">
      <summary class="collapse-title min-h-0 cursor-pointer font-medium">
        <span class="flex min-w-0 items-center gap-2">
          <Icon.icon name={@icon} class="h-4 w-4 shrink-0 opacity-70" />
          {@title}
        </span>
      </summary>
      <div class="collapse-content space-y-2">{render_slot(@inner_block)}</div>
    </details>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :min, :string, required: true
  attr :max, :string, required: true
  attr :step, :string, required: true

  defp range(assigns) do
    ~H"""
    <div class="pt-2">
      <div class="flex items-center justify-between gap-2 py-1">
        <span class="label-text min-w-0 text-xs">{@label}</span>
        <span
          class="text-xs font-medium tabular-nums opacity-80"
          {%{"data-poster-#{@name}-label" => true}}
        ></span>
      </div>
      <input
        type="range"
        min={@min}
        max={@max}
        step={@step}
        value="100"
        class="range range-primary range-xs"
        {%{"data-poster-#{@name}" => true}}
      />
    </div>
    """
  end

  def js(locale, key), do: t(locale, "javascript.poster." <> key, %{})

  defp p(locale, key, bindings \\ %{}), do: t(locale, "posters.studio." <> key, bindings)
end
