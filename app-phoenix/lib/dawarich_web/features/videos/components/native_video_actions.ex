defmodule DawarichWeb.NativeVideoActions do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  attr :locale, :string, required: true

  def video_actions(assigns) do
    ~H"""
    <label class="form-control">
      <span class="label-text text-xs">{v(@locale, "name")}</span>
      <input type="text" class="input input-bordered input-sm w-full" data-video-name />
    </label>
    <div class="hidden space-y-0.5 text-xs opacity-70 sm:block" data-video-summary></div>
    <div class="divider my-0 text-xs font-medium opacity-50">{v(@locale, "render_a_video")}</div>
    <div class="h-1 w-full overflow-hidden rounded-full bg-base-content/10">
      <div
        class="h-full origin-left rounded-full bg-primary transition-transform duration-150"
        style="transform: scaleX(0)"
        role="progressbar"
        aria-valuemin="0"
        aria-valuemax="100"
        aria-valuenow="0"
        data-video-progress
      >
      </div>
    </div>
    <p
      class="min-h-4 text-xs opacity-70 [overflow-wrap:anywhere]"
      aria-live="polite"
      data-video-status
    >
    </p>
    <button
      type="button"
      class="btn btn-primary btn-sm w-full"
      disabled
      data-video-render
      data-testid="video-render"
    >
      <Icon.icon name="play" class="h-4 w-4" />
      {v(@locale, "render_video")}
    </button>
    <button
      type="button"
      class="btn btn-ghost btn-xs hidden w-full gap-1 opacity-70"
      data-video-cancel
    >
      {v(@locale, "cancel")}
    </button>
    <button
      type="button"
      class="btn btn-ghost btn-xs w-full gap-1 opacity-70"
      disabled
      title={v(@locale, "keep_this_video_in_your_gallery")}
      data-video-save
      data-testid="video-save"
    >
      <Icon.icon name="camera" class="h-3.5 w-3.5" />
      {v(@locale, "save_to_gallery")}
    </button>
    """
  end

  defp v(locale, key), do: t(locale, "route_videos.studio." <> key, %{})
end
