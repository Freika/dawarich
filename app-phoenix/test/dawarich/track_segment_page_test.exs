defmodule Dawarich.TrackSegmentPageTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Repo, TrackSegmentPage}
  alias Dawarich.Test.FrameSeeds

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{owner: FrameSeeds.user!(8401), foreign: FrameSeeds.user!(8402)}
  end

  test "segments are owner scoped and ordered as the Rails controller", %{
    owner: owner,
    foreign: foreign
  } do
    attrs = %{start_at: ~N[2026-03-01 10:00:00], end_at: ~N[2026-03-01 11:00:00]}
    FrameSeeds.track!(owner.id, 84011, attrs)
    FrameSeeds.track!(foreign.id, 84012, attrs)

    FrameSeeds.segment!(84011, 840_102, %{
      start_index: 2,
      end_index: 3,
      transportation_mode: 2,
      start_at: ~U[2026-03-01 10:10:00Z],
      end_at: ~U[2026-03-01 10:20:00Z]
    })

    FrameSeeds.segment!(84011, 840_101, %{
      start_index: 1,
      end_index: 2,
      transportation_mode: 5,
      start_at: ~U[2026-03-01 10:00:00Z],
      end_at: ~U[2026-03-01 10:10:00Z]
    })

    FrameSeeds.segment!(84011, 840_103, %{start_index: 3, end_index: 4})
    assert {:ok, %{track_id: 84011, segments: rows}} = TrackSegmentPage.load(owner, 84011)
    assert Enum.map(rows, & &1.id) == [840_101, 840_102, 840_103]
    assert Enum.map(rows, & &1.transportation_mode) == ["driving", "walking", "unknown"]
    refute Map.has_key?(hd(rows), :path)
    assert :rails = TrackSegmentPage.load(owner, 84012)
    assert :rails = TrackSegmentPage.load(owner, 999_999)
    assert {:ok, %{segments: []}} = TrackSegmentPage.load(foreign, 84012)
    FrameSeeds.segment!(84011, 840_104, %{})
    FrameSeeds.segment!(84011, 840_105, %{})
    assert :rails = TrackSegmentPage.load(owner, 84011)
  end
end
