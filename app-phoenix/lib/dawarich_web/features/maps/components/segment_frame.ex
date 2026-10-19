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
  attr :native, :boolean, default: false

  def frame(%{native: true} = assigns) do
    assigns = assign(assigns, :display, DisplayLegs.call(assigns.segments))

    ~H"""
    <div id="native-segment-drawer" class="track-segments-list" data-native-track-id={@track_id}>
      <.list
        segments={@segments}
        display={@display}
        track_id={@track_id}
        user={@user}
        locale={@locale}
        csrf={@csrf}
        unit={@unit}
        now={@now}
        native={@native}
      />
    </div>
    """
  end

  def frame(assigns) do
    assigns = assign(assigns, :display, DisplayLegs.call(assigns.segments))

    ~H"""
    <turbo-frame id={"track-#{@track_id}-segments"} class="track-segments-list">
      <.list
        segments={@segments}
        display={@display}
        track_id={@track_id}
        user={@user}
        locale={@locale}
        csrf={@csrf}
        unit={@unit}
        now={@now}
        native={@native}
      />
    </turbo-frame>
    """
  end

  defp list(assigns) do
    ~H"""
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
            native={@native}
          />
          <details
            class="segment-rawlist"
            phx-mounted={@native && Phoenix.LiveView.JS.ignore_attributes(["open"])}
          >
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
                native={@native}
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
          native={@native}
        />
    <% end %>
    """
  end
end
