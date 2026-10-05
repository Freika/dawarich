defmodule DawarichWeb.ShareManagementDocument do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{ShareHub, ShareLinkActive, ShareLinkForm}

  def frame(assigns) do
    close_path = if assigns.page.trip, do: "/trips/#{assigns.page.trip.id}", else: "/map/v2"
    paths = ShareHub.paths(if(assigns.page.trip, do: assigns.page.trip.id, else: "live"))
    assigns = assigns |> assign(:close_path, close_path) |> assign(:paths, paths)

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
            <h3 class="font-bold text-lg mb-1">{title(@ctx, @page.trip)}</h3>
            <p class="text-sm text-base-content/70 mb-5">
              {if @page.trip,
                do: t(@ctx.locale, "shared_links.family.choose_audience", %{}),
                else: m(@ctx, "anyone_with_the_link_will_be_able_to_view_this")}
            </p>
            <ShareLinkForm.create
              ctx={@ctx}
              type={@type}
              paths={@paths}
              close_path={@close_path}
              start_date={nil}
              end_date={nil}
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
  defp title(ctx, trip), do: t(ctx.locale, "trips.share_links.new.share_trip", %{trip: trip.name})

  defp subtitle(ctx, nil, _share),
    do: t(ctx.locale, "share_links.lives.new.your_live_location_is_shared_via_a_public_link", %{})

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
