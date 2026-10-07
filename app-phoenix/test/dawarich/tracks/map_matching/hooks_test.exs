Code.require_file("support.exs", __DIR__)

defmodule Dawarich.Tracks.MapMatching.HooksTest do
  use Dawarich.TracksCase, async: false
  alias Dawarich.MapMatching.TestSupport
  alias Dawarich.Tracks.{Builder, Merger, Recalculator, Reprocessor, SegmentEditor, Store}
  alias Dawarich.Tracks.MapMatching.State

  setup do
    TestSupport.setup!()
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  for operation <- [
        :builder,
        :recalculator,
        :reprocessor,
        :reclassify,
        :merger,
        :segment_override,
        :segment_reset,
        :restore
      ] do
    @operation operation
    @tag operation
    test "#{operation} enqueues map matching for affected tracks once; a failing enqueue does not fail the operation" do
      track = fixture!(@operation)
      id = complete!(@operation, track)
      TestSupport.await_hooks!()
      track = %{track | id: id}
      assert id == track.id
      assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1
      assert State.read(ScratchRepo, track.id).status == :pending

      if repeatable?(@operation) do
        assert complete!(@operation, track) == track.id
        TestSupport.await_hooks!()
        assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1
      end

      failing = fixture!(@operation)
      TestSupport.fail_insert!(ScratchRepo)
      id = complete!(@operation, failing)
      TestSupport.await_hooks!()
      failing = %{failing | id: id}
      assert TestSupport.jobs(ScratchRepo, failing.id) == []
      assert State.read(ScratchRepo, failing.id).status == nil
      assert rows("SELECT id FROM tracks WHERE id=$1", [failing.id]) == [[failing.id]]
    end
  end

  defp repeatable?(operation), do: operation not in [:merger, :segment_reset]

  defp fixture!(operation) do
    track = TestSupport.input!(ScratchRepo)

    case operation do
      :builder ->
        rows("UPDATE points SET track_id=NULL WHERE track_id=$1", [track.id])
        rows("DELETE FROM track_segments WHERE track_id=$1", [track.id])
        rows("DELETE FROM tracks WHERE id=$1", [track.id])
        %{track | id: nil}

      kind when kind in [:segment_reset, :reclassify] ->
        rows("UPDATE track_segments SET source='user',corrected_at=now() WHERE track_id=$1", [
          track.id
        ])

        for offset <- [10, 20, 30, 40, 50] do
          point!(track.user.id, hd(track.points).timestamp + offset, 13.0 + offset / 60_000, 52.0,
            track_id: track.id
          )
        end

        track

      :merger ->
        older = Store.get(ScratchRepo, track.id)
        newer = track!(track.user.id, nil, older.end_at + 60, older.end_at + 120)
        point!(track.user.id, older.end_at + 60, 13.002, 52.0, track_id: newer)
        point!(track.user.id, older.end_at + 120, 13.003, 52.0, track_id: newer)
        Map.put(track, :newer, newer)

      _ ->
        track
    end
  end

  defp complete!(:builder, track) do
    assert {:ok, saved} =
             Builder.create_track!(ScratchRepo, track.user, track.points, 100,
               detector: &detect/3
             )

    if track.id, do: assert(saved.id == track.id)
    send(self(), {:built, saved.id})
    saved.id
  end

  defp complete!(:recalculator, track) do
    assert {:recalculated, %{id: id}} = Recalculator.run(ScratchRepo, track.id)
    id
  end

  defp complete!(:reprocessor, track) do
    assert %{id: id} =
             Reprocessor.reprocess!(
               ScratchRepo,
               track.user,
               Store.get(ScratchRepo, track.id),
               nil,
               detector: &detect/3
             )

    id
  end

  defp complete!(:reclassify, track) do
    assert :ok =
             Dawarich.Transportation.ReclassifyTrackWorker.run(ScratchRepo, oban(), %{
               "track_id" => track.id,
               "report_progress" => false,
               "user_id" => track.user.id
             })

    track.id
  end

  defp complete!(:merger, track) do
    assert true ==
             Merger.call(
               ScratchRepo,
               track.user,
               Store.get(ScratchRepo, track.id),
               Store.get(ScratchRepo, track.newer)
             )

    assert rows("SELECT id FROM tracks WHERE id=$1", [track.newer]) == []
    track.id
  end

  defp complete!(operation, track) when operation in [:segment_override, :segment_reset] do
    [[segment]] =
      rows("SELECT id FROM track_segments WHERE track_id=$1 ORDER BY id LIMIT 1", [track.id])

    context = %{now: ~U[2026-10-07 12:00:00.000000Z]}

    outcome =
      if operation == :segment_override,
        do:
          SegmentEditor.apply_override(
            ScratchRepo,
            track.user,
            track.id,
            segment,
            "cycling",
            context
          ),
        else: SegmentEditor.reset_to_auto(ScratchRepo, track.user, track.id, segment, context)

    assert {:ok, %{track: %{id: id}}} = outcome
    id
  end

  defp complete!(:restore, track) do
    row = %{
      "start_at" => ~N[2026-10-06 12:00:00],
      "end_at" => ~N[2026-10-06 12:01:00],
      "original_path" => "LINESTRING(13 52,13.001 52)",
      "distance" => 200,
      "duration" => 60,
      "avg_speed" => 6,
      "segments" => [
        %{
          "start_index" => 0,
          "end_index" => 1,
          "transportation_mode" => 2,
          "distance" => 200,
          "duration" => 60,
          "avg_speed" => 6,
          "max_speed" => 6
        }
      ]
    }

    assert 0 ==
             Dawarich.UserData.Restore.Tracks.call(ScratchRepo, track.user.id, [row], %{
               now: ~U[2026-10-07 12:00:00.000000Z],
               repo: ScratchRepo
             })

    assert rows("SELECT distance FROM tracks WHERE id=$1", [track.id]) == [[200]]
    track.id
  end

  defp detect(_repo, track, _opts) do
    [
      %{
        mode: "walking",
        start_at: track.start_at,
        end_at: track.end_at,
        path_wkt: "LINESTRING(13 52,13.001 52)",
        distance: 100,
        duration: 60,
        avg_speed: 6,
        max_speed: 6,
        confidence: "medium",
        confidence_score: 0.8,
        source: "inferred"
      }
    ]
  end
end
