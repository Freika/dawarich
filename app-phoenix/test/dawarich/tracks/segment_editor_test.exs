defmodule Dawarich.Tracks.SegmentEditorTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.{Repo, Tracks.SegmentEditor, Transportation.DominantMode}
  alias Dawarich.Test.FrameSeeds

  setup do
    user =
      FrameSeeds.user!(91961, %{
        "timezone" => "UTC",
        "enabled_transportation_modes" => ~w(walking cycling driving bus)
      })

    foreign = FrameSeeds.user!(91962)

    for {actor, id} <- [{user, 919_610}, {user, 919_611}, {foreign, 919_620}] do
      FrameSeeds.track!(actor.id, id, %{
        start_at: NaiveDateTime.add(~N[2026-10-03 09:00:00], id - 919_610),
        end_at: NaiveDateTime.add(~N[2026-10-03 09:10:00], id - 919_610),
        dominant_mode: 4
      })

      FrameSeeds.segment!(id, id * 10, %{
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

    %{user: user, ctx: %{now: ~U[2026-10-03 10:00:00.000000Z]}}
  end

  defp override(ctx, mode \\ "walking", track \\ 919_610, segment \\ 9_196_100),
    do: SegmentEditor.apply_override(Repo, ctx.user, track, segment, mode, ctx.ctx)

  defp snapshot do
    for table <- ~w(tracks track_segments),
        do: Repo.query!("SELECT to_jsonb(t)::text FROM #{table} t ORDER BY id").rows
  end

  test "override stamps correction confidence source dominant mode", ctx do
    assert {:ok, %{segment: %{id: 9_196_100}, track: %{dominant_mode: "walking"}}} = override(ctx)

    assert Repo.query!(
             "SELECT transportation_mode,corrected_at,confidence,confidence_score,source,updated_at FROM track_segments WHERE id=9196100"
           ).rows == [
             [2, ~N[2026-10-03 10:00:00.000000], 2, 1.0, "user", ~N[2026-10-03 10:00:00.000000]]
           ]
  end

  test "disabled mode changes no segment track or effects", ctx do
    before = snapshot()
    assert {:error, %{error_code: :mode_not_enabled}} = override(ctx, "flying")
    assert snapshot() == before
    assert commands() == []
  end

  test "nested ID cannot target another or foreign track", ctx do
    before = snapshot()

    for {track, segment} <- [
          {919_610, 9_196_110},
          {919_620, 9_196_200},
          {919_610, 9_196_200},
          {999_999, 9_196_100}
        ] do
      assert :rails = override(ctx, "walking", track, segment)
      assert snapshot() == before
      assert commands() == []
    end
  end

  test "persisted mode change publishes callback with lock_version", ctx do
    assert {:ok, _} = override(ctx)

    assert Repo.query!("SELECT dominant_mode,lock_version,updated_at FROM tracks WHERE id=919610").rows ==
             [[2, 1, ~N[2026-10-03 10:00:00.000000]]]

    assert [["tracks_changed", payload]] = commands()
    assert payload["updated"] == [919_610]
    assert payload["user_id"] == ctx.user.id
    assert payload["min_ts"] == 1_791_018_000
    assert payload["max_ts"] == 1_791_018_600
  end

  test "override unchanged nonnil mode keeps track timestamp and lock_version but emits epoch/broadcast intent",
       ctx do
    before = Repo.query!("SELECT updated_at,lock_version FROM tracks WHERE id=919610").rows
    assert {:ok, _} = override(ctx, "cycling")

    assert Repo.query!("SELECT updated_at,lock_version FROM tracks WHERE id=919610").rows ==
             before

    assert [["tracks_changed", %{"updated" => [919_610]}]] = commands()
  end

  test "tied dominance and no-mode preserve Rails order and old mode", ctx do
    FrameSeeds.segment!(919_610, 9_196_099, %{
      start_at: ~U[2026-10-03 09:11:00Z],
      end_at: ~U[2026-10-03 09:21:00Z],
      distance: 1000,
      duration: 600,
      transportation_mode: 2
    })

    assert {:ok, %{track: %{dominant_mode: "walking"}}} = override(ctx, "driving")
    assert Repo.query!("SELECT dominant_mode FROM tracks WHERE id=919610").rows == [[2]]
    assert DominantMode.pick([]) == nil
    invalid_before = snapshot()
    Repo.query!("UPDATE track_segments SET start_at=NULL,end_at=NULL WHERE id=9196100")
    legacy = snapshot()
    assert :rails = override(ctx)
    assert snapshot() == legacy
    refute snapshot() == invalid_before
  end
end
