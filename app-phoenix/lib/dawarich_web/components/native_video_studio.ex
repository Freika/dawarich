defmodule DawarichWeb.NativeVideoStudio do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.NativeVideoSections, only: [video_sections: 1]
  import DawarichWeb.NativeVideoActions, only: [video_actions: 1]

  alias Dawarich.I18n
  alias DawarichWeb.{Icon, PosterStudio}
  alias Phoenix.LiveView.JS

  @strings %{
    "open_failed" => "video.open_failed",
    "save_failed" => "video.save_failed",
    "rendering" => "video.rendering",
    "uploading" => "video.uploading",
    "ready" => "video.ready",
    "summary" => "video.summary",
    "unsupported_browser" => "video.unsupported_browser",
    "empty_track" => "video.empty_track",
    "restoring_range" => "video.restoring_range",
    "range_mismatch" => "video.range_mismatch",
    "stats.distance" => "video.stats.distance",
    "stats.duration" => "video.stats.duration",
    "stats.avg_speed" => "video.stats.avg_speed",
    "hud.day" => "video.hud.day",
    "hud.distance" => "video.hud.distance",
    "hud.of_total" => "video.hud.of_total",
    "hud.tagline" => "video.hud.tagline",
    "hud.travelled_over" => "video.hud.travelled_over",
    "start_before_end" => "datetime.start_before_end",
    "loading_tracks" => "poster.loading_tracks"
  }

  attr :themes, :list, required: true
  attr :locale, :string, required: true
  attr :fixed_range_label, :string, default: nil
  attr :target, :any, default: nil
  slot :gallery

  def video_studio(assigns) do
    assigns = assign(assigns, :config, config(assigns.locale))

    ~H"""
    <div
      id="native-video-studio"
      phx-hook="VideoStudio"
      phx-target={@target}
      data-video-config={@config}
    >
      <dialog
        id="native-video-dialog"
        data-video-dialog
        class="m-0 h-full max-h-none w-full max-w-none bg-base-300 p-0"
        aria-labelledby="native-video-title"
        phx-mounted={JS.ignore_attributes("open")}
      >
        <div class="flex h-full flex-col">
          <header class="flex flex-wrap items-center justify-between gap-2 border-b border-base-content/10 bg-base-200 px-3 py-2 sm:px-4">
            <div class="flex min-w-0 flex-wrap items-center gap-3">
              <h2
                id="native-video-title"
                class="flex min-w-0 items-center gap-2 text-sm font-semibold tracking-wide"
              >
                <Icon.icon name="video" class="h-4 w-4 shrink-0 opacity-70" />
                {v(@locale, "video_studio")}
              </h2>
              <div
                class="join shrink-0"
                role="group"
                aria-label={t(@locale, "shared.studio_switcher.studios", %{})}
              >
                <button
                  type="button"
                  class="btn btn-xs join-item btn-ghost gap-1"
                  aria-label={t(@locale, "shared.studio_switcher.poster", %{})}
                  data-testid="studio-switch-poster"
                  data-video-switch
                >
                  <Icon.icon name="image" class="h-3.5 w-3.5" />
                  <span class="hidden sm:inline">{t(@locale, "shared.studio_switcher.poster", %{})}</span>
                </button>
                <button
                  type="button"
                  class="btn btn-xs join-item btn-active gap-1"
                  aria-current="true"
                  data-testid="studio-switch-video"
                >
                  <Icon.icon name="video" class="h-3.5 w-3.5" />
                  <span class="hidden sm:inline">{t(@locale, "shared.studio_switcher.video", %{})}</span>
                </button>
              </div>
            </div>
            <div
              :if={is_nil(@fixed_range_label)}
              id="native-video-dates"
              phx-update="ignore"
              class="flex min-w-0 flex-1 flex-wrap items-center gap-2 lg:flex-none"
              role="group"
              aria-label={"#{d(@locale, "start_date_and_time")} — #{d(@locale, "end_date_and_time")}"}
              data-video-range-controls
            >
              <input
                type="datetime-local"
                class="input input-bordered input-sm min-w-0 flex-1 lg:w-56 lg:flex-none"
                max="9999-12-31T23:59"
                aria-label={d(@locale, "start_date_and_time")}
                data-video-start
              />
              <span class="text-xs opacity-60">–</span>
              <input
                type="datetime-local"
                class="input input-bordered input-sm min-w-0 flex-1 lg:w-56 lg:flex-none"
                max="9999-12-31T23:59"
                aria-label={d(@locale, "end_date_and_time")}
                data-video-end
              />
              <button
                type="button"
                class="btn btn-sm btn-primary h-auto shrink-0 py-1"
                data-video-load
              >
                <span
                  class="hidden h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-r-transparent"
                  data-video-load-spinner
                ></span>
                <span>{t(@locale, "posters.studio.load", %{})}</span>
              </button>
            </div>
            <div
              id="native-video-range"
              phx-update="ignore"
              class="flex min-w-0 items-center gap-2 text-sm opacity-70"
              data-video-range-display
            >
              <Icon.icon name="calendar-clock" class="h-4 w-4 shrink-0" />
              <span class="min-w-0 [overflow-wrap:anywhere]" data-video-range-label>
                {@fixed_range_label}
              </span>
            </div>
            <button
              type="button"
              class="btn btn-ghost btn-sm btn-circle shrink-0"
              title={v(@locale, "close_studio")}
              aria-label={v(@locale, "close_studio")}
              data-video-close
            >
              <Icon.icon name="x" class="size-6" />
            </button>
          </header>

          <div class="flex min-h-0 flex-1 flex-col lg:flex-row">
            <div
              id="native-video-stage"
              phx-update="ignore"
              class="relative flex h-[36vh] min-w-0 shrink-0 flex-col items-center justify-center overflow-hidden p-4 sm:p-6 lg:h-auto lg:flex-1 lg:shrink"
              data-video-stage
            >
              <div
                class="relative shrink-0 overflow-hidden border border-base-content/15 bg-base-100"
                data-video-frame
              >
                <div class="absolute inset-0" data-video-preview></div>
                <canvas class="pointer-events-none absolute inset-0 h-full w-full" data-video-overlay></canvas>
                <video
                  class="absolute inset-0 hidden h-full w-full bg-black"
                  controls
                  playsinline
                  data-video-result
                ></video>
              </div>
              <p class="mt-2 max-w-lg shrink-0 text-center text-xs leading-relaxed opacity-60">
                {v(@locale, "rendered_on_your_device_nothing_leaves_the_browser_until_you_save")}
              </p>
            </div>

            <aside class="flex min-h-0 w-full flex-1 flex-col border-t border-base-content/10 bg-base-200 lg:w-96 lg:flex-none lg:border-l lg:border-t-0">
              <div class="min-h-0 flex-1 space-y-2 overflow-y-auto p-3">
                <div id="native-video-controls" phx-update="ignore" class="space-y-2">
                  <.video_sections themes={@themes} locale={@locale} />
                </div>
                {render_slot(@gallery)}
              </div>
              <div
                id="native-video-actions"
                phx-update="ignore"
                class="shrink-0 space-y-2 border-t border-base-content/10 bg-base-100 p-3"
              >
                <.video_actions locale={@locale} />
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
      fonts: Jason.decode!(PosterStudio.fonts_json(~w(inter jetbrains-mono))),
      strings:
        Map.new(@strings, fn {key, path} ->
          {:ok, text} = I18n.template(locale, "javascript." <> path)
          {key, text}
        end)
    })
  end

  defp v(locale, key), do: t(locale, "route_videos.studio." <> key, %{})
  defp d(locale, key), do: t(locale, "shared.map.date_navigation_v2." <> key, %{})
end
