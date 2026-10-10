defmodule DawarichWeb.NativePosterStudio do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  import DawarichWeb.NativePosterSections, only: [poster_sections: 1]
  import DawarichWeb.NativePosterActions, only: [poster_actions: 1]
  import DawarichWeb.NativePosterCard, only: [poster_gallery: 1]

  alias DawarichWeb.{Icon, PosterFonts}
  alias Phoenix.LiveView.JS

  @strings %{
    "open_failed" => %{"error" => "%{error}"},
    "theme_load_failed" => %{"error" => "%{error}"},
    "load" => %{},
    "loading" => %{},
    "loading_tracks" => %{},
    "rendering" => %{"width" => "%{width}", "height" => "%{height}"},
    "saved" => %{},
    "saved_at_dpi" => %{"dpi" => "%{dpi}"},
    "export_failed" => %{"error" => "%{error}"},
    "queued" => %{},
    "untitled" => %{},
    "no_location_data" => %{},
    "no_tracks_in_frame" => %{},
    "frame_too_wide" => %{},
    "gallery_without_flights" => %{},
    "order_summary" => %{"layout" => "%{layout}", "price" => "%{price}"},
    "order_errors.wrong_size" => %{},
    "order_errors.too_large" => %{},
    "order_errors.unknown_sku" => %{},
    "order_errors.payment_unavailable" => %{},
    "order_errors.not_pdf" => %{},
    "order_errors.unreadable" => %{},
    "order_errors.generic" => %{},
    "order_errors.connection" => %{}
  }

  @shared_strings %{
    "save_failed" => "controllers.posters.failed_to_start_poster_generation"
  }

  attr :themes, :list, required: true
  attr :locale, :string, required: true
  attr :fixed_range_label, :string, default: nil
  attr :posters, :list, default: []
  attr :print_order_url, :string, default: ""

  def poster_studio(assigns) do
    assigns = assign(assigns, :config, config(assigns.locale, assigns.print_order_url))

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
              class="join shrink-0"
              role="group"
              aria-label={t(@locale, "shared.studio_switcher.studios", %{})}
            >
              <button
                type="button"
                class="btn btn-xs join-item btn-active gap-1"
                aria-current="true"
                data-testid="studio-switch-poster"
              >
                <Icon.icon name="image" class="h-3.5 w-3.5" />
                <span class="hidden sm:inline">{t(@locale, "shared.studio_switcher.poster", %{})}</span>
              </button>
              <button
                type="button"
                class="btn btn-xs join-item btn-ghost gap-1"
                aria-label={t(@locale, "shared.studio_switcher.video", %{})}
                data-testid="studio-switch-video"
                data-poster-switch-video
              >
                <Icon.icon name="video" class="h-3.5 w-3.5" />
                <span class="hidden sm:inline">{t(@locale, "shared.studio_switcher.video", %{})}</span>
              </button>
            </div>
            <div
              :if={is_nil(@fixed_range_label)}
              id="native-poster-dates"
              phx-update="ignore"
              class="flex min-w-0 flex-wrap items-center gap-2"
            >
              <input
                type="datetime-local"
                class="input input-bordered input-sm"
                aria-label={t(@locale, "shared.map.date_navigation_v2.start_date_and_time", %{})}
                data-poster-date-start
              />
              <span class="text-xs opacity-60">–</span>
              <input
                type="datetime-local"
                class="input input-bordered input-sm"
                aria-label={t(@locale, "shared.map.date_navigation_v2.end_date_and_time", %{})}
                data-poster-date-end
              />
              <button type="button" class="btn btn-sm btn-primary h-auto py-1" data-poster-load>
                <span
                  class="hidden h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-r-transparent"
                  data-poster-load-spinner
                ></span>
                <span data-poster-load-label>{p(@locale, "load")}</span>
              </button>
              <div class="hidden items-center gap-1 lg:flex">
                <button
                  :for={
                    {range, label} <- [
                      {"today", "today"},
                      {"week", "last_7_days"},
                      {"month", "last_month"}
                    ]
                  }
                  type="button"
                  class="btn btn-sm btn-ghost"
                  data-poster-range={range}
                >
                  {p(@locale, label)}
                </button>
              </div>
            </div>
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
              <div class="min-h-0 flex-1 overflow-y-auto">
                <div id="native-poster-controls" phx-update="ignore" class="space-y-3 p-3">
                  <.poster_sections themes={@themes} locale={@locale} />
                </div>
                <details
                  id="native-poster-gallery"
                  class="collapse collapse-arrow mx-3 mb-3 rounded-lg bg-base-100"
                  phx-mounted={JS.ignore_attributes("open")}
                >
                  <summary class="collapse-title min-h-0 cursor-pointer font-medium">
                    <span class="flex min-w-0 items-center gap-2">
                      <Icon.icon name="camera" class="h-4 w-4 shrink-0 opacity-70" />
                      {p(@locale, "recent_posters")}
                    </span>
                  </summary>
                  <div class="collapse-content space-y-3">
                    <p class="text-xs opacity-60">
                      {p(@locale, "server_rendered_posters_from_save_to_gallery_they_stay_here")}
                    </p>
                    <.poster_gallery posters={@posters} locale={@locale} />
                  </div>
                </details>
              </div>
              <div
                id="native-poster-actions"
                phx-update="ignore"
                class="space-y-2 border-t border-base-content/10 p-3"
              >
                <.poster_actions locale={@locale} />
              </div>
            </aside>
          </div>
        </div>
      </dialog>
    </div>
    """
  end

  def config(locale, print_order_url \\ "") do
    Jason.encode!(%{
      fonts: PosterFonts.urls(),
      printOrderUrl: print_order_url || "",
      strings:
        @strings
        |> Map.new(fn {key, bindings} ->
          {key, t(locale, "javascript.poster." <> key, bindings)}
        end)
        |> Map.merge(Map.new(@shared_strings, fn {key, path} -> {key, t(locale, path, %{})} end))
    })
  end

  defp p(locale, key, bindings \\ %{}), do: t(locale, "posters.studio." <> key, bindings)
end
