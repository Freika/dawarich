defmodule DawarichWeb.SegmentFrameTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias DawarichWeb.{SegmentFormat, SegmentFrame, TimelineFormat}

  defp segment(attrs \\ %{}) do
    Map.merge(
      %{
        id: 83601,
        track_id: 8360,
        start_at: nil,
        end_at: nil,
        duration: 600,
        distance: 1000,
        transportation_mode: "walking",
        confidence_score: 0.8,
        corrected_at: nil
      },
      attrs
    )
  end

  defp frame(rows, unit \\ "km", modes \\ ["walking", "driving"]) do
    render_component(&SegmentFrame.frame/1,
      track_id: 8360,
      segments: rows,
      user: %{settings: %{"enabled_transportation_modes" => modes}},
      unit: unit,
      locale: "en",
      csrf: "CSRF",
      now: ~U[2026-10-03 10:00:00Z]
    )
  end

  defp attr(html, selector, name),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  test "empty legacy and condensed frames have exact Turbo target ids" do
    empty = frame([])
    assert attr(empty, "turbo-frame", "id") == ["track-8360-segments"]
    assert empty =~ "No segments for this track yet"
    legacy = frame([segment()])
    assert attr(legacy, "turbo-frame", "id") == ["track-8360-segments", "segment-row-83601"]
    refute legacy =~ "segment-ribbon"

    condensed =
      frame([segment(%{start_at: ~U[2026-10-03 08:00:00Z], end_at: ~U[2026-10-03 08:10:00Z]})])

    assert attr(condensed, "turbo-frame", "id") == ["track-8360-segments", "segment-row-83601"]
    assert attr(condensed, ".segment-legs", "id") == ["track-8360-legs"]
    assert attr(condensed, "summary", "data-testid") == ["segment-rawlist-toggle-8360"]
  end

  test "row and leg forms retain Rails PATCH scopes and reset controls" do
    html =
      frame([
        segment(%{
          start_at: ~U[2026-10-03 08:00:00Z],
          end_at: ~U[2026-10-03 08:10:00Z],
          corrected_at: ~U[2026-10-03 09:00:00Z]
        })
      ])

    assert attr(html, "form", "action") == List.duplicate("/tracks/8360/segments/83601", 2)
    assert attr(html, "form", "method") == ["post", "post"]
    assert attr(html, "input[name='_method']", "value") == ["patch", "patch"]
    assert attr(html, "input[name='authenticity_token']", "value") == ["CSRF", "CSRF"]
    assert attr(html, "select", "name") == List.duplicate("track_segment[transportation_mode]", 2)
    assert attr(html, "button[name='reset']", "value") == ["true"]
    assert attr(html, ".segment-row form", "data-turbo-frame") == ["segment-row-83601"]
    assert attr(html, "form", "phx-submit") == []

    assert attr(html, "select", "data-action") ==
             List.duplicate("change->segment-mode-editor#submit", 2)
  end

  test "disabled current mode is first and enabled modes keep their order" do
    user = %{settings: %{"enabled_transportation_modes" => ["driving", "walking"]}}

    assert SegmentFormat.modes_for_mode("cycling", user, "en") ==
             [
               {"Cycling (disabled in settings)", "cycling"},
               {"Driving", "driving"},
               {"Walking", "walking"}
             ]

    html = frame([segment(%{transportation_mode: "cycling"})], "km", ["driving", "walking"])
    assert attr(html, "option", "value") == ["cycling", "driving", "walking"]
    assert attr(html, "option[selected]", "value") == ["cycling"]
  end

  test "corrected rows show relative age but omit confidence" do
    html = frame([segment(%{corrected_at: ~U[2026-10-03 09:00:00Z]})])
    assert html =~ "Edited about 1 hour ago"
    refute html =~ "80%"
    assert frame([segment()]) =~ "80%"
    refute frame([segment(%{confidence_score: nil})]) =~ "Detection confidence"
  end

  test "distance duration and ribbon markup match Rails units and rounding" do
    assert SegmentFormat.segment_distance(nil, "mi", "en") == "-"
    assert SegmentFormat.segment_distance(12345, "mi", "en") == "7.67 mi"
    assert SegmentFormat.segment_distance(1000, "km", "en") == "1.0 km"

    html =
      frame([segment(%{start_at: ~U[2026-10-03 08:00:00Z], end_at: ~U[2026-10-03 08:10:00Z]})])

    assert attr(html, ".segment-ribbon i", "style") == ["width: 100.0%; background: #22C55E"]
    assert html =~ "10m"
  end

  test "raw nil duration renders a dash" do
    assert SegmentFormat.segment_duration(nil, "en") == "-"
    assert frame([segment(%{duration: nil})]) =~ "-"
  end

  test "raw zero duration uses units minutes" do
    assert SegmentFormat.segment_duration(0, "en") == "0 min"
  end

  test "raw sub-hour duration uses full minutes units" do
    assert SegmentFormat.segment_duration(89, "en") == "1 min"
    assert SegmentFormat.segment_duration(3599, "en") == "59 min"
  end

  test "raw day-plus duration keeps unbounded hours unlike the same-duration condensed leg" do
    assert SegmentFormat.segment_duration(90060, "en") == "25h 1m"
    assert TimelineFormat.duration_short("en", 90060) == "1d 1h"
  end
end
