defmodule DawarichWeb.PosterStudio do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapParts, only: [studio_switcher: 1]
  import DawarichWeb.PosterStudioSections, only: [poster_sections: 1]
  import DawarichWeb.PosterStudioActions, only: [poster_actions: 1]

  alias DawarichWeb.Icon

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def poster_studio(assigns) do
    assigns = assign(assigns, fonts: fonts_json(~w(inter oswald playfair-display jetbrains-mono)))

    ~H"""
    <div
      id="poster-studio"
      class="fixed inset-0 hidden bg-base-300"
      style="z-index: 60"
      data-controller="poster-studio-editor"
      data-poster-studio-editor-fonts-value={@fonts}
      data-poster-studio-editor-print-order-url-value={@page.print_order_url}
    >
      <div class="flex h-full flex-col">
        <header class="flex items-center justify-between gap-4 border-b border-base-content/10 bg-base-200 px-4 py-2">
          <div class="flex items-center gap-3 shrink-0">
            <h2 class="text-sm font-semibold tracking-wide flex items-center gap-2">
              <Icon.icon name="map" class="h-4 w-4 opacity-70" />
              {p(@locale, "poster_studio")}
            </h2>
            <.studio_switcher current={:poster} controller="poster-studio-editor" locale={@locale} />
          </div>
          <div class="flex items-center gap-2 min-w-0">
            <input
              type="datetime-local"
              class="input input-bordered input-sm"
              data-poster-studio-editor-target="dateStart"
            />
            <span class="text-xs opacity-60">–</span>
            <input
              type="datetime-local"
              class="input input-bordered input-sm"
              data-poster-studio-editor-target="dateEnd"
            />
            <button
              type="button"
              class="btn btn-sm btn-primary"
              data-poster-studio-editor-target="loadButton"
              data-action="poster-studio-editor#applyDates"
            >
              <span
                class="hidden h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-r-transparent"
                data-poster-studio-editor-target="loadSpinner"
              ></span>
              <span data-poster-studio-editor-target="loadLabel">{p(@locale, "load")}</span>
            </button>
            <div class="hidden items-center gap-1 lg:flex">
              <button
                type="button"
                class="btn btn-sm btn-ghost"
                data-range="today"
                data-action="poster-studio-editor#presetRange"
              >{p(@locale, "today")}</button>
              <button
                type="button"
                class="btn btn-sm btn-ghost"
                data-range="week"
                data-action="poster-studio-editor#presetRange"
              >{p(@locale, "last_7_days")}</button>
              <button
                type="button"
                class="btn btn-sm btn-ghost"
                data-range="month"
                data-action="poster-studio-editor#presetRange"
              >{p(@locale, "last_month")}</button>
            </div>
          </div>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-circle shrink-0"
            title={p(@locale, "close_studio")}
            data-action="poster-studio-editor#close"
          >
            <Icon.icon name="x" class="size-6" />
          </button>
        </header>

        <div class="flex min-h-0 flex-1">
          <div
            class="relative flex min-w-0 flex-1 flex-col items-center justify-center overflow-hidden p-6"
            data-poster-studio-editor-target="stage"
          >
            <img
              class="pointer-events-none absolute inset-0 h-full w-full object-cover opacity-0 transition-opacity duration-500"
              style="filter: blur(22px) brightness(0.5) saturate(1.15); transform: scale(1.15)"
              alt=""
              data-poster-studio-editor-target="backdrop"
            />
            <div
              class="relative shrink-0 overflow-hidden shadow-2xl"
              data-poster-studio-editor-target="frame"
            >
              <div
                style="position: absolute; inset: 0"
                data-poster-studio-editor-target="mapContainer"
              >
              </div>
              <canvas
                class="absolute inset-0 h-full w-full"
                style="pointer-events: none"
                data-poster-studio-editor-target="overlay"
              ></canvas>
            </div>
            <div class="mt-4 flex items-center gap-2">
              <button type="button" class="btn btn-sm" data-action="poster-studio-editor#recenter">
                <Icon.icon name="compass" class="h-4 w-4" />
                {p(@locale, "recenter")}
              </button>
            </div>
            <p class="mt-2 text-xs opacity-60">
              {p(@locale, "drag_to_pan_scroll_to_zoom_the_frame_is_what")}
            </p>
          </div>

          <aside class="flex w-96 shrink-0 flex-col border-l border-base-content/10 bg-base-200">
            <.poster_sections page={@page} locale={@locale} />
            <.poster_actions page={@page} locale={@locale} rails_csrf_token={@rails_csrf_token} />
          </aside>
        </div>
      </div>
    </div>
    """
  end

  def fonts_json(families) do
    families
    |> Enum.flat_map(fn family ->
      for weight <- ~w(400 700),
          do:
            {"#{family}-#{weight}",
             DawarichWeb.Assets.stylesheet_path("poster/#{family}-#{weight}.woff2")}
    end)
    |> Jason.OrderedObject.new()
    |> Jason.encode!()
  end

  defp p(locale, key), do: t(locale, "posters.studio." <> key, %{})
end
