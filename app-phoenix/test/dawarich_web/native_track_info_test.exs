defmodule DawarichWeb.NativeTrackInfoTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "native track information labels and trackless journey controls are localized and bounded" do
    track = %{
      id: 17,
      distance: 1609,
      avg_speed: 6.0,
      elevation_gain: 3,
      elevation_loss: 2,
      mode: "cycling",
      started_at: "2026-03-30T11:00:00+02:00",
      points: false
    }

    entry = %{
      track_id: nil,
      dominant_mode: "cycling",
      start_local: ~N[2026-03-30 11:00:00],
      duration: 600,
      distance: 1.0,
      distance_unit: "km",
      started_at: track.started_at,
      ended_at: "2026-03-30T11:10:00+02:00"
    }

    for locale <- Dawarich.I18n.available_locales() do
      html =
        render_component(&DawarichWeb.TimelineCalendar.track_info_frame/1,
          track: track,
          unit: "mi",
          locale: locale,
          native: true
        )

      refute html =~ "translation_missing"
      assert html =~ "1.0 mi"
      assert html =~ "track:points"
      assert html =~ "data-native-track-replay"

      leg =
        render_component(&DawarichWeb.TimelineJourney.journey_entry/1,
          entry: entry,
          locale: locale,
          native: true
        )

      refute leg =~ "translation_missing"
      refute leg =~ "track:toggle"
      refute leg =~ "segments:open"
      refute leg =~ "turbo-frame"
    end
  end
end
