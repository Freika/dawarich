defmodule Dawarich.ReleaseOperations.OrphanedTracksTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import ExUnit.CaptureLog

  alias Dawarich.ReleaseOperations.OrphanedTracks
  alias Dawarich.Wave6Fixtures

  setup do
    Wave6Fixtures.reset!()
    first = Wave6Fixtures.user!()
    second = Wave6Fixtures.user!()

    orphan =
      Wave6Fixtures.track!(first, %{
        "start_at" => ~N[2020-03-01 10:00:00],
        "end_at" => ~N[2020-03-01 11:00:00]
      })

    later_orphan =
      Wave6Fixtures.track!(first, %{
        "start_at" => ~N[2020-03-02 10:00:00],
        "end_at" => ~N[2020-03-02 12:00:00]
      })

    other_orphan =
      Wave6Fixtures.track!(second, %{
        "start_at" => ~N[2020-04-01 08:00:00],
        "end_at" => ~N[2020-04-01 09:00:00]
      })

    kept = Wave6Fixtures.track!(first)
    Wave6Fixtures.point!(first, %{"track_id" => kept})

    segments = Enum.map([orphan, later_orphan, other_orphan, kept], &Wave6Fixtures.segment!/1)

    %{
      first: first,
      second: second,
      orphans: [orphan, later_orphan, other_orphan],
      kept: kept,
      kept_segment: List.last(segments)
    }
  end

  test "deletes orphan tracks and their segments and keeps tracks with points", ctx do
    assert OrphanedTracks.run(ScratchRepo) == :ok

    assert rows("SELECT id FROM tracks") == [[ctx.kept]]
    assert rows("SELECT id FROM track_segments") == [[ctx.kept_segment]]
  end

  test "writes one tracks_changed per user with the destroyed ids and range", ctx do
    [orphan, later_orphan, other_orphan] = ctx.orphans

    assert OrphanedTracks.run(ScratchRepo) == :ok

    commands =
      for [kind, payload] <-
            rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY payload->'user_id'"),
          do: [kind, Map.update!(payload, "destroyed", &Enum.sort/1)]

    assert commands ==
             [
               [
                 "tracks_changed",
                 %{
                   "user_id" => ctx.first,
                   "created" => [],
                   "updated" => [],
                   "destroyed" => [orphan, later_orphan],
                   "min_ts" => epoch(~N[2020-03-01 10:00:00]),
                   "max_ts" => epoch(~N[2020-03-02 12:00:00])
                 }
               ],
               [
                 "tracks_changed",
                 %{
                   "user_id" => ctx.second,
                   "created" => [],
                   "updated" => [],
                   "destroyed" => [other_orphan],
                   "min_ts" => epoch(~N[2020-04-01 08:00:00]),
                   "max_ts" => epoch(~N[2020-04-01 09:00:00])
                 }
               ]
             ]
  end

  test "a point re-pointed at an orphan mid-sweep aborts that batch and the sweep ends", ctx do
    point = Wave6Fixtures.point!(ctx.first)
    test = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("UPDATE points SET track_id = $1 WHERE id = $2", [
            hd(ctx.orphans),
            point
          ])

          send(test, :held)

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive :held, 5_000

    Logger.put_module_level(OrphanedTracks, :info)
    on_exit(fn -> Logger.delete_module_level(OrphanedTracks) end)
    sweep = Task.async(fn -> with_log(fn -> OrphanedTracks.run(ScratchRepo) end) end)

    Wave6Fixtures.await_waiter!("SELECT t.id, t.user_id%")
    send(holder.pid, :commit)
    assert {:ok, :ok} = Task.await(holder)

    assert {:ok, log} = Task.await(sweep)
    assert log =~ "event=tracks.orphan_delete_aborted count=3"
    assert length(rows("SELECT id FROM tracks")) == 4
    assert length(rows("SELECT id FROM track_segments")) == 4
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  test "the sweep pages past a full batch of 1,000 by id", ctx do
    rows(
      """
      INSERT INTO tracks (user_id, start_at, end_at, original_path, created_at, updated_at)
      SELECT $1, timestamp '2021-01-01' + g * interval '1 hour',
        timestamp '2021-01-01' + g * interval '1 hour' + interval '30 minutes',
        ST_GeomFromText('LINESTRING(12.3731 51.3397, 12.3831 51.3497)', 4326), now(), now()
      FROM generate_series(1, 1001) g
      """,
      [ctx.second]
    )

    assert OrphanedTracks.perform(%Oban.Job{args: %{"version" => 1}}) == :ok

    assert rows("SELECT id FROM tracks") == [[ctx.kept]]
  end

  test "perform cancels an unsupported version" do
    assert OrphanedTracks.perform(%Oban.Job{args: %{"version" => 2}}) ==
             {:cancel, :unsupported_version}
  end

  defp epoch(naive), do: naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
end
