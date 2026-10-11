defmodule DawarichWeb.VideoStudioMore do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapGalleryCards, only: [route_video_card: 1]

  alias DawarichWeb.Icon

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def video_more(assigns) do
    ~H"""
    <details open class="collapse collapse-arrow rounded-lg border border-base-content/10 bg-base-100">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="route" class="h-4 w-4 opacity-70 shrink-0" />
          {v(@locale, "route")}
        </span>
      </summary>
      <div class="collapse-content space-y-3">
        <div class="grid grid-cols-2 gap-2 pb-2">
          <label class="label min-h-11 cursor-pointer justify-start gap-2 rounded-md border border-base-content/10 bg-base-200/60 px-3 py-2 transition-colors hover:bg-base-300/60">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              data-setting="show_route"
              data-action="change->video-studio#updateSetting"
            />
            <span class="label-text text-xs">{v(@locale, "show_route")}</span>
          </label>
          <label class="label min-h-11 cursor-pointer justify-start gap-2 rounded-md border border-base-content/10 bg-base-200/60 px-3 py-2 transition-colors hover:bg-base-300/60">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              data-setting="show_marker"
              data-action="change->video-studio#updateSetting"
            />
            <span class="label-text text-xs">{v(@locale, "show_marker")}</span>
          </label>
        </div>
        <div class="flex items-center gap-2">
          <label
            for="video-track-color"
            class="flex min-w-0 flex-1 cursor-pointer items-center gap-3 rounded-md border border-base-content/10 bg-base-200/60 p-2 transition-colors hover:bg-base-300/60"
          >
            <input
              id="video-track-color"
              type="color"
              class="h-9 w-11 shrink-0 cursor-pointer rounded border border-base-content/15 bg-base-100 p-1"
              aria-label={v(@locale, "track_color")}
              data-setting="track_color"
              data-action="input->video-studio#updateSetting"
            />
            <span class="min-w-0">
              <span class="block text-xs">{v(@locale, "track_color")}</span>
              <span
                class="block truncate text-xs tabular-nums opacity-60"
                data-video-studio-target="trackColorLabel"
              ></span>
            </span>
          </label>
          <button
            type="button"
            class="btn btn-ghost btn-sm shrink-0"
            data-action="video-studio#resetTrackColor"
          >
            {v(@locale, "reset")}
          </button>
        </div>
        <div>
          <div class="flex items-center justify-between">
            <label id="video-track-width-label" for="video-track-width" class="label-text text-xs">
              {v(@locale, "track_width")}
            </label>
            <output
              class="text-xs font-medium tabular-nums opacity-80"
              for="video-track-width"
              data-video-studio-target="trackWidthLabel"
            ></output>
          </div>
          <input
            id="video-track-width"
            type="range"
            min="50"
            max="300"
            step="10"
            class="range range-primary range-xs"
            aria-labelledby="video-track-width-label"
            data-setting="track_width"
            data-action="input->video-studio#updateSetting"
          />
        </div>
      </div>
    </details>

    <details class="collapse collapse-arrow rounded-lg border border-base-content/10 bg-base-100">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="play" class="h-4 w-4 opacity-70 shrink-0" />
          {v(@locale, "playback")}
        </span>
      </summary>
      <div class="collapse-content space-y-2">
        <div>
          <div class="flex items-center justify-between py-1">
            <label id="video-duration-label" for="video-duration" class="label-text text-xs">{v(
              @locale,
              "duration"
            )}</label>
            <output
              class="text-xs font-medium tabular-nums opacity-80"
              for="video-duration"
              data-video-studio-target="durationLabel"
            ></output>
          </div>
          <input
            id="video-duration"
            type="range"
            min="8"
            max="30"
            step="1"
            class="range range-primary range-xs"
            aria-labelledby="video-duration-label"
            data-setting="duration_sec"
            data-action="input->video-studio#updateSetting"
          />
        </div>
        <label class="form-control">
          <span class="label-text text-xs">{v(@locale, "camera")}</span>
          <select
            class="select select-bordered select-sm py-0 w-full"
            data-setting="camera_mode"
            data-action="change->video-studio#updateSetting"
          >
            <option value="overview">{v(@locale, "camera_overview")}</option>
            <option value="follow">{v(@locale, "camera_follow")}</option>
          </select>
        </label>
        <label class="form-control">
          <span class="label-text text-xs">{v(@locale, "units")}</span>
          <select
            class="select select-bordered select-sm py-0 w-full"
            data-setting="units"
            data-action="change->video-studio#updateSetting"
          >
            <option value="km">{v(@locale, "units_km")}</option>
            <option value="mi">{v(@locale, "units_mi")}</option>
          </select>
        </label>
        <div>
          <div class="flex items-center justify-between py-1">
            <label id="video-hud-scale-label" for="video-hud-scale" class="label-text text-xs">
              {v(@locale, "hud_scale")}
            </label>
            <output
              class="text-xs font-medium tabular-nums opacity-80"
              for="video-hud-scale"
              data-video-studio-target="hudScaleLabel"
            ></output>
          </div>
          <input
            id="video-hud-scale"
            type="range"
            min="80"
            max="140"
            step="5"
            class="range range-primary range-xs"
            aria-labelledby="video-hud-scale-label"
            data-setting="hud_scale"
            data-action="input->video-studio#updateSetting"
          />
        </div>
        <label class="label cursor-pointer justify-start gap-3 py-1">
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-primary"
            data-setting="watermark"
            data-action="change->video-studio#updateSetting"
          />
          <span class="label-text text-sm">{v(@locale, "watermark")}</span>
        </label>
      </div>
    </details>

    <details class="collapse collapse-arrow rounded-lg border border-base-content/10 bg-base-100">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="camera" class="h-4 w-4 opacity-70 shrink-0" />
          {v(@locale, "recent_videos")}
        </span>
      </summary>
      <div class="collapse-content space-y-3">
        <p class="text-xs opacity-60">{v(@locale, "videos_from_save_to_gallery_they_stay_here")}</p>
        <div id="route-video-gallery-list" class="space-y-3">
          <.route_video_card :for={video <- @page.route_videos} video={video} locale={@locale} />
        </div>
      </div>
    </details>
    """
  end

  defp v(locale, key), do: t(locale, "route_videos.studio." <> key, %{})
end
