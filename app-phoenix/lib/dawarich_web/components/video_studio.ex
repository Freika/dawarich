defmodule DawarichWeb.VideoStudio do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapParts, only: [studio_switcher: 1]
  import DawarichWeb.PosterStudio, only: [fonts_json: 1]
  import DawarichWeb.VideoStudioSections, only: [video_sections: 1]
  import DawarichWeb.VideoStudioMore, only: [video_more: 1]

  alias DawarichWeb.Icon

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :base_url, :string, required: true

  def video_studio(assigns) do
    assigns =
      assign(assigns,
        fonts: fonts_json(~w(inter jetbrains-mono)),
        upload_url: assigns.base_url <> "/rails/active_storage/direct_uploads",
        create_url: "/route_videos",
        range_label:
          "#{d(assigns.locale, "start_date_and_time")} — #{d(assigns.locale, "end_date_and_time")}"
      )

    ~H"""
    <div
      id="video-studio"
      class="fixed inset-0 hidden bg-base-300"
      style="z-index: 60"
      data-controller="video-studio"
      data-video-studio-fonts-value={@fonts}
      data-video-studio-upload-url-value={@upload_url}
      data-video-studio-create-url-value={@create_url}
    >
      <div class="flex h-full flex-col">
        <header class="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-2 border-b border-base-content/10 bg-base-200 px-3 py-2 sm:px-4 lg:grid-cols-[auto_minmax(0,1fr)_auto_auto]">
          <div class="flex items-center gap-3 shrink-0">
            <h2 class="text-sm font-semibold tracking-wide flex items-center gap-2">
              <Icon.icon name="video" class="h-4 w-4 opacity-70" />
              {v(@locale, "video_studio")}
            </h2>
            <.studio_switcher current={:video} controller="video-studio" locale={@locale} />
          </div>
          <div
            class="col-span-2 row-start-2 flex min-w-0 items-center gap-2 lg:col-span-1 lg:row-start-auto lg:justify-self-center"
            role="group"
            aria-label={@range_label}
            data-video-studio-target="rangeControls"
          >
            <label class="min-w-0 flex-1 lg:w-56 lg:flex-none">
              <span class="sr-only">{d(@locale, "start_date_and_time")}</span>
              <input
                type="datetime-local"
                class="input input-bordered input-sm w-full"
                max="9999-12-31T23:59"
                aria-label={d(@locale, "start_date_and_time")}
                data-video-studio-target="dateStart"
              />
            </label>
            <span class="text-xs opacity-60">–</span>
            <label class="min-w-0 flex-1 lg:w-56 lg:flex-none">
              <span class="sr-only">{d(@locale, "end_date_and_time")}</span>
              <input
                type="datetime-local"
                class="input input-bordered input-sm w-full"
                max="9999-12-31T23:59"
                aria-label={d(@locale, "end_date_and_time")}
                data-video-studio-target="dateEnd"
              />
            </label>
            <button
              type="button"
              class="btn btn-sm btn-primary shrink-0"
              data-video-studio-target="loadButton"
              data-action="video-studio#applyDateTimeRange"
            >
              <span
                class="hidden h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-r-transparent"
                data-video-studio-target="loadSpinner"
              ></span>
              <span>{t(@locale, "posters.studio.load", %{})}</span>
            </button>
          </div>
          <div
            class="min-w-0 items-center gap-2 text-sm opacity-70 lg:flex lg:justify-self-center"
            data-video-studio-target="rangeDisplay"
          >
            <Icon.icon name="calendar-clock" class="h-4 w-4 shrink-0" />
            <span class="truncate" data-video-studio-target="rangeLabel"></span>
          </div>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-circle shrink-0 justify-self-end"
            title={v(@locale, "close_studio")}
            aria-label={v(@locale, "close_studio")}
            data-action="video-studio#close"
          >
            <Icon.icon name="x" class="size-6" />
          </button>
        </header>

        <div class="flex min-h-0 flex-1 flex-col lg:flex-row">
          <div
            class="relative flex h-[36vh] min-w-0 shrink-0 flex-col items-center justify-center overflow-hidden p-4 sm:p-6 lg:h-auto lg:flex-1 lg:shrink"
            data-video-studio-target="stage"
          >
            <div
              class="relative shrink-0 overflow-hidden border border-base-content/15 bg-base-100"
              data-video-studio-target="frame"
            >
              <div style="position: absolute; inset: 0" data-video-studio-target="preview"></div>
              <canvas
                class="absolute inset-0 h-full w-full"
                style="pointer-events: none"
                data-video-studio-target="overlay"
              ></canvas>
              <video
                class="absolute inset-0 hidden h-full w-full bg-black"
                data-video-studio-target="result"
                controls
                playsinline
              ></video>
            </div>
            <p class="mt-2 max-w-lg shrink-0 text-center text-xs leading-relaxed opacity-60">
              {v(@locale, "rendered_on_your_device_nothing_leaves_the_browser_until_you_save")}
            </p>
          </div>

          <aside class="flex min-h-0 w-full flex-1 flex-col border-t border-base-content/10 bg-base-200 lg:w-96 lg:flex-none lg:border-l lg:border-t-0">
            <div class="min-h-0 flex-1 space-y-2 overflow-y-auto p-3">
              <.video_sections page={@page} locale={@locale} />
              <.video_more page={@page} locale={@locale} />
            </div>

            <div class="shrink-0 space-y-2 border-t border-base-content/10 bg-base-100 p-3">
              <label class="form-control">
                <span class="label-text text-xs">{v(@locale, "name")}</span>
                <input
                  type="text"
                  class="input input-bordered input-sm w-full"
                  data-video-studio-target="nameInput"
                />
              </label>

              <div
                class="hidden space-y-0.5 text-xs opacity-70 sm:block"
                data-video-studio-target="summary"
              >
              </div>

              <div class="divider my-0 text-xs font-medium opacity-50">
                {v(@locale, "render_a_video")}
              </div>

              <div class="h-1 w-full overflow-hidden rounded-full bg-base-content/10">
                <div
                  class="h-full origin-left rounded-full bg-primary transition-transform duration-150"
                  style="transform: scaleX(0)"
                  role="progressbar"
                  aria-valuemin="0"
                  aria-valuemax="100"
                  aria-valuenow="0"
                  data-video-studio-target="progressBar"
                >
                </div>
              </div>
              <p
                class="min-h-4 text-xs opacity-70"
                aria-live="polite"
                data-video-studio-target="status"
              >
              </p>

              <button
                type="button"
                class="btn btn-primary btn-sm w-full"
                data-video-studio-target="renderButton"
                data-action="video-studio#render"
                data-testid="video-render"
              >
                <Icon.icon name="play" class="h-4 w-4" />
                {v(@locale, "render_video")}
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs w-full gap-1 opacity-70 hidden"
                data-video-studio-target="cancelButton"
                data-action="video-studio#cancel"
              >{v(@locale, "cancel")}</button>
              <button
                type="button"
                class="btn btn-ghost btn-xs w-full gap-1 opacity-70"
                disabled
                data-video-studio-target="saveButton"
                data-action="video-studio#save"
                data-testid="video-save"
                title={v(@locale, "keep_this_video_in_your_gallery")}
              >
                <Icon.icon name="camera" class="h-3.5 w-3.5" />
                {v(@locale, "save_to_gallery")}
              </button>
            </div>
          </aside>
        </div>
      </div>
    </div>
    """
  end

  defp v(locale, key), do: t(locale, "route_videos.studio." <> key, %{})
  defp d(locale, key), do: t(locale, "shared.map.date_navigation_v2." <> key, %{})
end
