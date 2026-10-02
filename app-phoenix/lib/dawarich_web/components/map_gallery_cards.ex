defmodule DawarichWeb.MapGalleryCards do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.MapGallery
  alias DawarichWeb.LocalizedTime

  @phases %{
    "fetching_data" => {"fetching_data", 1},
    "drawing_map" => {"drawing_map", 2},
    "drawing_route" => {"drawing_route", 3},
    "saving" => {"saving", 4}
  }
  @completed 2
  @failed 3
  @stored 0

  attr :poster, :map, required: true
  attr :locale, :string, required: true

  def poster_card(assigns) do
    image = assigns.poster.files["image"]
    pdf = assigns.poster.files["print_pdf"]
    completed = assigns.poster.status == @completed
    {label_key, step} = Map.get(@phases, assigns.poster.settings["progress_phase"], {"queued", 0})

    assigns =
      assign(assigns,
        image: completed && image,
        pdf: completed && pdf,
        completed: completed,
        failed: assigns.poster.status == @failed,
        phase_label: t(assigns.locale, "helpers.posters.render_phases." <> label_key, %{}),
        step: step
      )

    ~H"""
    <div id={"poster_#{@poster.id}"} class="card bg-base-200 shadow-sm">
      <figure :if={@image}>
        <img src={MapGallery.blob_path(@image)} class="w-full rounded-t-lg" />
      </figure>
      <div class="card-body p-3">
        <h4 class="card-title text-sm">{@poster.name}</h4>
        <%= cond do %>
          <% @failed -> %>
            <p class="text-error text-xs">{@poster.settings["error"]}</p>
          <% not @completed -> %>
            <p class="text-xs opacity-70 flex items-center gap-2">
              <span class="loading loading-spinner loading-xs"></span> {@phase_label}
            </p>
            <progress class="progress progress-primary w-full" value={to_string(@step)} max="4"></progress>
          <% true -> %>
        <% end %>
        <div class="card-actions justify-end">
          <a
            :if={@image}
            class="btn btn-xs btn-ghost"
            href={MapGallery.blob_path(@image, "attachment")}
          >{p(@locale, "download_png")}</a>
          <a :if={@pdf} class="btn btn-xs btn-primary" href={MapGallery.blob_path(@pdf, "attachment")}>{p(
            @locale,
            "download_pdf"
          )}</a>
          <a
            class="btn btn-xs btn-ghost"
            data-turbo-method="delete"
            data-turbo-confirm={p(@locale, "delete_this_poster")}
            href={"/posters/#{@poster.id}"}
          >{p(@locale, "delete")}</a>
        </div>
      </div>
    </div>
    """
  end

  attr :video, :map, required: true
  attr :locale, :string, required: true

  def route_video_card(assigns) do
    file = assigns.video.files["file"]

    assigns =
      assign(assigns, file: file, playable: assigns.video.status == @stored and file != nil)

    ~H"""
    <div id={"route_video_#{@video.id}"} class="card bg-base-200 shadow-sm">
      <figure :if={@playable}>
        <video
          class="w-full rounded-t-lg"
          controls
          preload="metadata"
          playsinline
          src={MapGallery.blob_path(@file)}
        ></video>
      </figure>
      <div class="card-body p-3">
        <h4 class="card-title text-sm min-w-0 break-words">{@video.name}</h4>
        <%= unless @playable do %>
          <p class="text-xs opacity-70">
            {v(@locale, "expired_on", %{date: LocalizedTime.l(@locale, @video.shown_at, "long")})}
          </p>
          <p class="text-xs opacity-50">{v(@locale, "expired_hint")}</p>
        <% end %>
        <div class="card-actions justify-end">
          <%= if @playable do %>
            <a class="btn btn-xs btn-primary" href={MapGallery.blob_path(@file, "attachment")}>{v(
              @locale,
              "download"
            )}</a>
          <% else %>
            <button
              type="button"
              class="btn btn-xs btn-ghost"
              data-action="video-studio#restoreSettings"
              data-settings={@video.settings_json}
            >
              {v(@locale, "re_render")}
            </button>
          <% end %>
          <a
            class="btn btn-xs btn-ghost"
            data-turbo-method="delete"
            data-turbo-confirm={v(@locale, "delete_this_video")}
            href={"/route_videos/#{@video.id}"}
          >{v(@locale, "delete")}</a>
        </div>
      </div>
    </div>
    """
  end

  defp p(locale, key), do: t(locale, "posters.poster." <> key, %{})

  defp v(locale, key, bindings \\ %{}),
    do: t(locale, "route_videos.route_video." <> key, bindings)
end
