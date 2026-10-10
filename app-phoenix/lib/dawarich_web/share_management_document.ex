defmodule DawarichWeb.ShareManagementDocument do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{ShareHub, ShareLinkActive, ShareLinkForm}

  def frame(assigns) do
    track? = assigns.type == "track"

    close_path =
      if assigns.page.trip && !track?, do: "/trips/#{assigns.page.trip.id}", else: "/map/v2"

    paths =
      if track?,
        do:
          Map.new(ShareHub.paths(assigns.page.trip.id), fn {key, path} ->
            {key, String.replace(path, "/trips/", "/tracks/")}
          end),
        else: ShareHub.paths(if(assigns.page.trip, do: assigns.page.trip.id, else: assigns.type))

    {:ok, range} =
      Dawarich.ShareManagement.Read.hub(
        %{id: assigns.ctx.user_id, settings: assigns.ctx.settings},
        %{},
        assigns.ctx.now
      )

    assigns =
      assigns |> assign(:close_path, close_path) |> assign(:paths, paths) |> assign(:range, range)

    ~H"""
    <turbo-frame id="share-link-modal" phx-hook="RailsStimulus" phx-update="ignore">
      <div class="modal modal-open" data-controller="share-link-modal" style="z-index: 10000;">
        <div class="modal-box max-w-xl">
          <a
            class="btn btn-sm btn-circle btn-ghost absolute right-3 top-3"
            data-turbo-frame="_top"
            data-action="share-link-modal#close"
            aria-label={m(@ctx, "close")}
            href={@close_path}
          >✕</a>
          <%= if @page.share do %>
            <ShareLinkActive.active
              ctx={@ctx}
              share={@page.share}
              paths={@paths}
              subtitle={subtitle(@ctx, @page.trip, @page.share)}
            />
          <% else %>
            <h3 class="font-bold text-lg mb-1">
              {if @type == "timeline",
                do: t(@ctx.locale, "share_links.timelines.new.share_a_date_range", %{}),
                else: title(@ctx, @page.trip)}
            </h3>
            <p class="text-sm text-base-content/70 mb-5">
              {if @type == "trip",
                do: t(@ctx.locale, "shared_links.family.choose_audience", %{}),
                else: m(@ctx, "anyone_with_the_link_will_be_able_to_view_this")}
            </p>
            <ShareLinkForm.create
              ctx={@ctx}
              type={@type}
              paths={@paths}
              close_path={@close_path}
              errors={Map.get(@page, :errors, [])}
              start_date={Map.get(@page, :start_date, @range.start_date)}
              end_date={Map.get(@page, :end_date, @range.end_date)}
            />
          <% end %>
        </div>
        <a
          class="modal-backdrop"
          data-turbo-frame="_top"
          data-action="share-link-modal#close"
          aria-label={m(@ctx, "close")}
          href={@close_path}
        ></a>
      </div>
    </turbo-frame>
    """
  end

  defp title(ctx, nil), do: t(ctx.locale, "share_links.lives.new.share_your_live_location", %{})

  defp title(ctx, %{type: "track"} = track),
    do: t(ctx.locale, "tracks.share_links.new.share_track", %{track: track.name})

  defp title(ctx, trip), do: t(ctx.locale, "trips.share_links.new.share_trip", %{trip: trip.name})

  defp subtitle(ctx, nil, %{type: "timeline", settings: settings}) do
    range =
      DawarichWeb.SharedPages.date_range(
        ctx.locale,
        Date.from_iso8601!(settings["start_date"]),
        Date.from_iso8601!(settings["end_date"])
      )

    t(ctx.locale, "helpers.shared_links.timeline_subtitle", %{range: range})
  end

  defp subtitle(ctx, nil, _share),
    do: t(ctx.locale, "share_links.lives.new.your_live_location_is_shared_via_a_public_link", %{})

  defp subtitle(ctx, %{type: "track"}, _share),
    do: t(ctx.locale, "tracks.share_links.new.this_track_is_shared_via_a_public_link", %{})

  defp subtitle(ctx, trip, share),
    do:
      t(
        ctx.locale,
        if(Dawarich.SharedLinks.FamilyAudience.family_only?(share),
          do: "shared_links.family.shared_trip",
          else: "trips.share_links.new.trip_is_shared_via_a_public_link"
        ),
        %{trip: trip.name}
      )

  defp m(ctx, key), do: t(ctx.locale, "shared_links.modal." <> key, %{})
end
