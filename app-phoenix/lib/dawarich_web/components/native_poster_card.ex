defmodule DawarichWeb.NativePosterCard do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.MapGallery

  @phases %{
    "fetching_data" => {"fetching_data", 1},
    "drawing_map" => {"drawing_map", 2},
    "drawing_route" => {"drawing_route", 3},
    "saving" => {"saving", 4}
  }

  attr :posters, :list, required: true
  attr :locale, :string, required: true

  def poster_gallery(assigns) do
    ~H"""
    <div id="native-poster-gallery-list" class="space-y-3">
      <.poster_card :for={poster <- @posters} poster={poster} locale={@locale} />
    </div>
    """
  end

  attr :poster, :map, required: true
  attr :locale, :string, required: true

  def poster_card(assigns) do
    completed = assigns.poster.status == 2
    {label, step} = Map.get(@phases, assigns.poster.settings["progress_phase"], {"queued", 0})

    assigns =
      assign(assigns,
        image: completed && assigns.poster.files["image"],
        pdf: completed && assigns.poster.files["print_pdf"],
        completed: completed,
        failed: assigns.poster.status == 3,
        phase_label: t(assigns.locale, "helpers.posters.render_phases." <> label, %{}),
        step: step
      )

    ~H"""
    <div id={"poster_#{@poster.id}"} class="card bg-base-200 shadow-sm" data-poster-card>
      <figure :if={@image}>
        <img src={MapGallery.blob_path(@image)} class="w-full rounded-t-lg" alt="" />
      </figure>
      <div class="card-body p-3">
        <h4 class="card-title min-w-0 text-sm [overflow-wrap:anywhere]">{@poster.name}</h4>
        <%= cond do %>
          <% @failed -> %>
            <p class="text-xs text-error [overflow-wrap:anywhere]">{@poster.settings["error"]}</p>
          <% not @completed -> %>
            <p class="flex items-center gap-2 text-xs opacity-70" role="status">
              <span class="loading loading-spinner loading-xs"></span> {@phase_label}
            </p>
            <progress class="progress progress-primary w-full" value={to_string(@step)} max="4"></progress>
          <% true -> %>
        <% end %>
        <div class="card-actions flex-wrap justify-end">
          <a
            :if={@image}
            class="btn btn-xs btn-ghost"
            href={MapGallery.blob_path(@image, "attachment")}
          >
            {p(@locale, "download_png")}
          </a>
          <a :if={@pdf} class="btn btn-xs btn-primary" href={MapGallery.blob_path(@pdf, "attachment")}>
            {p(@locale, "download_pdf")}
          </a>
          <button
            type="button"
            class="btn btn-xs btn-ghost"
            phx-click="poster:delete"
            phx-value-id={@poster.id}
            data-confirm={p(@locale, "delete_this_poster")}
          >
            {p(@locale, "delete")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp p(locale, key), do: t(locale, "posters.poster." <> key, %{})
end
