defmodule DawarichWeb.SegmentFrame do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.TrackSegments.DisplayLegs
  alias DawarichWeb.{SegmentLegs, SegmentRow}

  attr :track_id, :integer, required: true
  attr :segments, :list, required: true
  attr :user, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :unit, :string, required: true
  attr :now, DateTime, required: true

  def frame(assigns) do
    assigns = assign(assigns, :display, DisplayLegs.call(assigns.segments))

    ~H"""
    <turbo-frame id={"track-#{@track_id}-segments"} class="track-segments-list">
      <%= cond do %>
        <% @segments == [] -> %>
          <p class="text-sm text-base-content/60">
            {t(@locale, "tracks.segments.index.no_segments_for_this_track_yet", %{})}
          </p>
        <% @display -> %>
          <div class="track-segments">
            <SegmentLegs.legs
              display={@display}
              track_id={@track_id}
              user={@user}
              locale={@locale}
              csrf={@csrf}
              unit={@unit}
            />
            <details class="segment-rawlist">
              <summary data-testid={"segment-rawlist-toggle-#{@track_id}"}>
                {t(@locale, "tracks.segments.list.all_segments", %{count: length(@segments)})}
              </summary>
              <div class="segment-rawlist__rows">
                <SegmentRow.row
                  :for={segment <- @segments}
                  segment={segment}
                  user={@user}
                  locale={@locale}
                  csrf={@csrf}
                  unit={@unit}
                  now={@now}
                />
              </div>
            </details>
          </div>
        <% true -> %>
          <SegmentRow.row
            :for={segment <- @segments}
            segment={segment}
            user={@user}
            locale={@locale}
            csrf={@csrf}
            unit={@unit}
            now={@now}
          />
      <% end %>
    </turbo-frame>
    """
  end
end
