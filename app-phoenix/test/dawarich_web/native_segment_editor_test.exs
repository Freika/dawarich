defmodule DawarichWeb.NativeSegmentEditorTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint

  setup do
    [id, other] = for _ <- 1..2, do: System.unique_integer([:positive])

    FrameSeeds.user!(id, %{
      "timezone" => "UTC",
      "enabled_transportation_modes" => ~w(walking cycling driving)
    })

    FrameSeeds.user!(other)
    track = id * 10
    foreign = other * 10

    for {owner, track_id} <- [{id, track}, {other, foreign}] do
      FrameSeeds.track!(owner, track_id, %{
        start_at: ~N[2026-10-03 09:00:00],
        end_at: ~N[2026-10-03 09:10:00],
        dominant_mode: 4
      })

      FrameSeeds.segment!(track_id, track_id * 10, %{
        start_at: ~U[2026-10-03 09:00:00Z],
        end_at: ~U[2026-10-03 09:10:00Z],
        distance: 1000,
        duration: 600,
        avg_speed: 6.0,
        transportation_mode: 4,
        source: "inferred",
        confidence: 1,
        confidence_score: 0.7
      })
    end

    %{id: id, track: track, foreign: foreign}
  end

  test "native drawer loads bounded segments and saves a scoped mode override", c do
    view = open(c.id)
    render_hook(view, "segments:open", %{"track_id" => to_string(c.foreign)})
    refute has_element?(view, "#native-segment-drawer")

    render_hook(view, "segments:open", %{"track_id" => to_string(c.track)})
    segment = c.track * 10
    assert has_element?(view, "#native-segment-#{segment} select option[value='walking']")
    refute has_element?(view, "#native-segment-#{segment} select option[value='flying']")

    view
    |> form("#native-segment-#{segment} form", %{
      "track_segment" => %{"transportation_mode" => "walking"}
    })
    |> render_change()

    assert_push_event(view, "map:invalidate", %{resource: "tracks", id: track_id})
    assert track_id == c.track

    assert rows("SELECT transportation_mode, source FROM track_segments WHERE id=$1", [segment]) ==
             [[2, "user"]]

    assert has_element?(view, "#native-segment-#{segment} [aria-label='Manually corrected']")

    render_hook(view, "segment:mode", %{
      "segment_id" => to_string(c.foreign * 10),
      "mode" => "walking"
    })

    assert rows("SELECT source FROM track_segments WHERE id=$1", [c.foreign * 10]) == [
             ["inferred"]
           ]

    render_hook(view, "segment:mode", %{"segment_id" => to_string(segment), "mode" => "flying"})
    assert has_element?(view, "p.alert-error[role=alert]")
  end

  test "native segment correction keeps persisted feedback without replacing the map", c do
    view = open(c.id)
    render_hook(view, "segments:open", %{"track_id" => to_string(c.track)})

    view
    |> form("#native-segment-#{c.track * 10} form", %{
      "track_segment" => %{"transportation_mode" => "walking"}
    })
    |> render_change()

    assert has_element?(view, "p[role=status]", "Segment updated")
    assert has_element?(view, "#native-segment-#{c.track * 10} [aria-label='Manually corrected']")
    assert rows("SELECT source FROM track_segments WHERE id=$1", [c.track * 10]) == [["user"]]

    render_hook(view, "segment:mode", %{
      "segment_id" => to_string(c.track * 10),
      "mode" => "flying"
    })

    assert has_element?(view, "p.alert-error[role=alert]")
    refute has_element?(view, "p[role=status]")
  end

  defp open(id) do
    {:ok, view, _} =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Map.merge(%{request_path: "/map/v2", path_info: ["map", "v2"], query_string: ""})
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeMapShellRouter.call([])
      |> live()

    view
  end
end
