defmodule DawarichWeb.VideoStudioSections do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.{Assets, Icon}

  @formats [
    {"portrait", "format_portrait", "9:16", "h-8 w-[18px]"},
    {"landscape", "format_landscape", "16:9", "h-6 w-11"},
    {"square", "format_square", "1:1", "h-8 w-8"}
  ]

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def video_sections(assigns) do
    assigns =
      assign(assigns,
        formats:
          Enum.map(@formats, fn {key, label_key, ratio, preview_class} ->
            {key, v(assigns.locale, label_key), ratio, preview_class}
          end)
      )

    ~H"""
    <details class="collapse collapse-arrow rounded-lg border border-base-content/10 bg-base-100">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="grid2x2" class="h-4 w-4 opacity-70 shrink-0" />
          {v(@locale, "format")}
        </span>
      </summary>
      <div class="collapse-content space-y-2">
        <div
          class="grid grid-cols-3 gap-1 rounded-lg bg-base-200 p-1"
          role="radiogroup"
          aria-label={v(@locale, "format")}
        >
          <button
            :for={{key, label, ratio, preview_class} <- @formats}
            type="button"
            class="btn btn-sm h-auto min-h-20 flex-col gap-2 border-0 px-2 py-3"
            role="radio"
            title={label}
            aria-label={label}
            data-video-studio-target="formatOption"
            data-format={key}
            data-format-label={label}
            data-action="video-studio#selectFormat"
          >
            <span class="flex h-8 w-12 items-center justify-center" aria-hidden="true">
              <span class={"#{preview_class} rounded-sm border-2 border-current opacity-80"}></span>
            </span>
            <span class="min-w-0 text-center leading-tight">
              <span class="block truncate text-xs font-medium">{label
              |> String.split(" · ", parts: 2)
              |> hd()}</span>
              <span class="block text-[10px] font-bold uppercase tracking-[0.05em] opacity-60">{ratio}</span>
            </span>
          </button>
        </div>
        <p class="text-center text-xs tabular-nums opacity-60" data-video-studio-target="formatDims">
        </p>
      </div>
    </details>

    <details open class="collapse collapse-arrow rounded-lg border border-base-content/10 bg-base-100">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="cloud-fog" class="h-4 w-4 opacity-70 shrink-0" />
          {v(@locale, "visualization")}
        </span>
      </summary>
      <div class="collapse-content space-y-3">
        <div>
          <span class="label-text text-xs">{v(@locale, "mode")}</span>
          <div
            class="mt-1 grid grid-cols-2 gap-1 rounded-lg bg-base-200 p-1"
            role="radiogroup"
            aria-label={v(@locale, "mode")}
          >
            <button
              type="button"
              class="btn btn-sm h-auto min-h-10 justify-center gap-2 border-0 px-3 py-2"
              role="radio"
              data-video-studio-target="visualizationMode"
              data-visualization-mode="route"
              data-action="video-studio#selectVisualizationMode"
            >
              <Icon.icon name="route" class="h-4 w-4 shrink-0" />
              <span class="truncate">{v(@locale, "mode_route")}</span>
            </button>
            <button
              type="button"
              class="btn btn-sm h-auto min-h-10 justify-center gap-2 border-0 px-3 py-2"
              role="radio"
              data-video-studio-target="visualizationMode"
              data-visualization-mode="fog"
              data-action="video-studio#selectVisualizationMode"
            >
              <Icon.icon name="cloud-fog" class="h-4 w-4 shrink-0" />
              <span class="truncate">{v(@locale, "mode_fog")}</span>
            </button>
          </div>
        </div>
        <div
          class="space-y-3 rounded-md border border-base-content/10 bg-base-200/60 p-3"
          data-video-studio-target="fogControls"
        >
          <div class="flex items-center gap-2">
            <label
              for="video-fog-color"
              class="flex min-w-0 flex-1 cursor-pointer items-center gap-3 rounded-md border border-base-content/10 bg-base-100 p-2 transition-colors hover:bg-base-200"
            >
              <input
                id="video-fog-color"
                type="color"
                class="h-9 w-11 shrink-0 cursor-pointer rounded border border-base-content/15 bg-base-100 p-1"
                aria-label={v(@locale, "fog_color")}
                data-setting="fog_color"
                data-action="input->video-studio#updateSetting"
              />
              <span class="min-w-0">
                <span class="block text-xs">{v(@locale, "fog_color")}</span>
                <span
                  class="block truncate text-xs tabular-nums opacity-60"
                  data-video-studio-target="fogColorLabel"
                ></span>
              </span>
            </label>
            <button
              type="button"
              class="btn btn-ghost btn-sm shrink-0"
              data-action="video-studio#resetFogColor"
            >
              {v(@locale, "reset")}
            </button>
          </div>
          <div class="flex items-center justify-between">
            <label id="video-fog-opacity-label" for="video-fog-opacity" class="label-text text-xs">
              {v(@locale, "fog_opacity")}
            </label>
            <output
              class="text-xs font-medium tabular-nums opacity-80"
              for="video-fog-opacity"
              data-video-studio-target="fogOpacityLabel"
            ></output>
          </div>
          <input
            id="video-fog-opacity"
            type="range"
            min="0"
            max="100"
            step="5"
            class="range range-primary range-xs"
            aria-labelledby="video-fog-opacity-label"
            data-setting="fog_opacity"
            data-action="input->video-studio#updateSetting"
          />
        </div>
      </div>
    </details>

    <details class="collapse collapse-arrow rounded-lg border border-base-content/10 bg-base-100">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="palette" class="h-4 w-4 opacity-70 shrink-0" />
          {v(@locale, "theme")}
        </span>
      </summary>
      <div class="collapse-content space-y-2">
        <div class="grid grid-cols-6 gap-1.5">
          <button
            :for={theme <- @page.themes}
            type="button"
            class="h-10 w-full overflow-hidden rounded-md border border-base-content/15 ring-primary ring-offset-base-100 transition-transform hover:scale-105 focus:outline-none focus-visible:ring-2 sm:h-8"
            style={"background-image: url('#{Assets.stylesheet_path("poster_themes/#{theme.key}.webp")}'); background-size: cover; background-position: center;"}
            title={to_string(theme.name)}
            aria-label={to_string(theme.name)}
            data-video-studio-target="themeSwatch"
            data-theme-key={theme.key}
            data-theme-name={to_string(theme.name)}
            data-action="click->video-studio#selectTheme"
          ></button>
        </div>
        <p class="text-xs opacity-70" data-video-studio-target="themeLabel"></p>
      </div>
    </details>
    """
  end

  defp v(locale, key), do: t(locale, "route_videos.studio." <> key, %{})
end
