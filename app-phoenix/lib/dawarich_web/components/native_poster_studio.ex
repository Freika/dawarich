defmodule DawarichWeb.NativePosterStudio do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.{Assets, Icon, PosterFonts}
  alias Phoenix.LiveView.JS

  @strings %{
    "open_failed" => %{"error" => "%{error}"},
    "theme_load_failed" => %{"error" => "%{error}"}
  }

  attr :themes, :list, required: true
  attr :locale, :string, required: true
  attr :fixed_range_label, :string, default: nil

  def poster_studio(assigns) do
    assigns = assign(assigns, :config, config(assigns.locale))

    ~H"""
    <div id="native-poster-studio" phx-hook="PosterStudio" data-poster-config={@config}>
      <dialog
        id="native-poster-dialog"
        data-poster-dialog
        class="m-0 h-full max-h-none w-full max-w-none bg-base-300 p-0"
        aria-labelledby="native-poster-title"
        phx-mounted={JS.ignore_attributes("open")}
      >
        <div class="flex h-full flex-col">
          <header class="flex flex-wrap items-center justify-between gap-2 border-b border-base-content/10 bg-base-200 px-4 py-2">
            <h2
              id="native-poster-title"
              class="flex min-w-0 items-center gap-2 text-sm font-semibold tracking-wide"
            >
              <Icon.icon name="map" class="h-4 w-4 shrink-0 opacity-70" />
              {p(@locale, "poster_studio")}
            </h2>
            <div
              :if={@fixed_range_label}
              class="flex min-w-0 items-center gap-2 text-sm opacity-70"
            >
              <Icon.icon name="calendar-clock" class="h-4 w-4 shrink-0" />
              <span class="min-w-0 [overflow-wrap:anywhere]">{@fixed_range_label}</span>
            </div>
            <form method="dialog" class="shrink-0">
              <button
                class="btn btn-ghost btn-sm btn-circle"
                title={p(@locale, "close_studio")}
                aria-label={p(@locale, "close_studio")}
              >
                <Icon.icon name="x" class="size-6" />
              </button>
            </form>
          </header>

          <div class="flex min-h-0 flex-1 flex-col lg:flex-row">
            <div
              id="native-poster-stage"
              phx-update="ignore"
              data-poster-stage
              class="relative flex min-h-[60vh] min-w-0 flex-1 flex-col items-center justify-center overflow-hidden p-6 lg:min-h-0"
            >
              <img
                data-poster-backdrop
                class="pointer-events-none absolute inset-0 h-full w-full object-cover opacity-0 transition-opacity duration-500"
                style="filter: blur(22px) brightness(0.5) saturate(1.15); transform: scale(1.15)"
                alt=""
              />
              <div data-poster-frame class="relative shrink-0 overflow-hidden shadow-2xl">
                <div data-poster-map style="position: absolute; inset: 0"></div>
                <canvas
                  data-poster-overlay
                  class="absolute inset-0 h-full w-full"
                  style="pointer-events: none"
                ></canvas>
              </div>
              <div class="mt-4 flex items-center gap-2">
                <button type="button" class="btn btn-sm" data-poster-recenter>
                  <Icon.icon name="compass" class="h-4 w-4" />
                  {p(@locale, "recenter")}
                </button>
              </div>
              <p class="mt-2 text-center text-xs opacity-60">
                {p(@locale, "drag_to_pan_scroll_to_zoom_the_frame_is_what")}
              </p>
            </div>

            <aside class="flex w-full shrink-0 flex-col border-t border-base-content/10 bg-base-200 lg:w-96 lg:border-l lg:border-t-0">
              <div
                id="native-poster-controls"
                phx-update="ignore"
                class="min-h-0 flex-1 space-y-3 overflow-y-auto p-3"
              >
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
                  >
                  </button>
                </div>
                <p class="text-xs opacity-70" data-poster-theme-label></p>
                <p class="text-xs opacity-70" role="status" data-poster-status></p>
              </div>
            </aside>
          </div>
        </div>
      </dialog>
    </div>
    """
  end

  def config(locale) do
    Jason.encode!(%{
      fonts: PosterFonts.urls(),
      strings:
        Map.new(@strings, fn {key, bindings} ->
          {key, t(locale, "javascript.poster." <> key, bindings)}
        end)
    })
  end

  defp p(locale, key, bindings \\ %{}), do: t(locale, "posters.studio." <> key, bindings)
end
