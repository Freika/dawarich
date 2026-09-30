defmodule Dawarich.Tracks.GenerationTest do
  use Dawarich.TracksCase

  alias Dawarich.Tracks.{BoundaryWorker, Generation}

  @stalled "Max retries (5) exceeded waiting for chunks to complete"

  defp chunks(n) do
    for i <- 0..(n - 1),
        do: %{
          chunk_id: i,
          start_ts: 1_000 * i,
          end_ts: 1_000 * i + 999,
          buffer_start_ts: 1_000 * i,
          buffer_end_ts: 1_000 * i + 999
        }
  end

  defp start!(n, opts \\ []) do
    id = Ecto.UUID.generate()

    args = %{
      "event_id" => id,
      "user_id" => 1,
      "mode" => "bulk",
      "untracked_only" => false,
      "import_id" => nil,
      "low_priority" => false
    }

    {Generation.start!(ScratchRepo, oban(), args, chunks(n), opts), id}
  end

  defp jobs do
    rows(
      "SELECT worker, args, priority, round(extract(epoch FROM scheduled_at - inserted_at))::int " <>
        "FROM oban.oban_jobs ORDER BY id"
    )
  end

  defp look(id, poll_count),
    do:
      BoundaryWorker.run(ScratchRepo, oban(), %{"generation_id" => id, "poll_count" => poll_count})

  defp boundary_jobs(poll_count) do
    rows(
      "SELECT round(extract(epoch FROM scheduled_at - inserted_at))::int FROM oban.oban_jobs " <>
        "WHERE worker = $1 AND (args->>'poll_count')::int = $2",
      [inspect(BoundaryWorker), poll_count]
    )
  end

  test "start! commits generation, chunks and jobs together or not at all" do
    assert_raise RuntimeError, "boom", fn ->
      start!(2, hook: fn :inserted -> raise "boom" end)
    end

    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.track_generation_chunks") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]

    {:started, id} = start!(2)

    assert [
             ["Dawarich.Tracks.ChunkWorker", %{"generation_id" => ^id, "chunk_id" => 0}, 1, 0],
             ["Dawarich.Tracks.ChunkWorker", %{"generation_id" => ^id, "chunk_id" => 1}, 1, 0],
             [
               "Dawarich.Tracks.BoundaryWorker",
               %{"generation_id" => ^id, "poll_count" => 0},
               1,
               300
             ]
           ] = jobs()

    assert generation(id) == [["running", 2, 0, 0, 0, nil]]

    assert rows(
             "SELECT chunk_id, start_ts, end_ts, buffer_start_ts, buffer_end_ts, status " <>
               "FROM phoenix.track_generation_chunks ORDER BY chunk_id"
           ) == [[0, 0, 999, 0, 999, "pending"], [1, 1_000, 1_999, 1_000, 1_999, "pending"]]
  end

  test "a chunk completes once" do
    {:started, id} = start!(2)

    assert Generation.chunk_done!(ScratchRepo, id, 0, 3) == 1
    assert Generation.chunk_done!(ScratchRepo, id, 0, 3) == nil

    assert rows("SELECT completed_chunks, tracks_created FROM phoenix.track_generations") == [
             [1, 3]
           ]
  end

  test "a replayed poll does not schedule twice" do
    {:started, id} = start!(2)

    assert look(id, 0) == :ok
    assert look(id, 0) == :ok

    assert boundary_jobs(1) == [[30]]
    assert generation(id) == [["running", 2, 0, 1, 0, nil]]
  end

  test "five stalled looks fail the generation; progress resets the count" do
    {:started, id} = start!(3)

    stalls =
      for poll_count <- 0..8 do
        if poll_count == 3, do: Generation.chunk_done!(ScratchRepo, id, 0, 0)
        :ok = look(id, poll_count)
        [[status, _, _, _, stall_count, _]] = generation(id)
        {status, stall_count}
      end

    assert stalls == [
             {"running", 0},
             {"running", 1},
             {"running", 2},
             {"running", 0},
             {"running", 1},
             {"running", 2},
             {"running", 3},
             {"running", 4},
             {"failed", 5}
           ]

    assert generation(id) == [["failed", 3, 1, 9, 5, @stalled]]

    assert Enum.map(1..9, &boundary_jobs/1) == [
             [[30]],
             [[60]],
             [[120]],
             [[240]],
             [[300]],
             [[300]],
             [[300]],
             [[300]],
             []
           ]
  end

  test "terminal states are never left" do
    {:started, failed} = start!(1)
    {:started, completed} = start!(1)

    for id <- [failed, completed], do: 1 = Generation.chunk_done!(ScratchRepo, id, 0, 0)

    assert Generation.fail!(ScratchRepo, failed, "boom")
    refute Generation.complete!(ScratchRepo, failed)

    assert Generation.complete!(ScratchRepo, completed)
    refute Generation.fail!(ScratchRepo, completed, "boom")

    assert [["failed" | _]] = generation(failed)
    assert [["completed", 1, 1, 0, 0, nil]] = generation(completed)
  end

  test "chunk jobs are inserted in bounded batches" do
    parent = self()
    name = oban()
    handler = "generation-insert-batches-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:oban, :engine, :insert_all_jobs, :start],
      fn _event, _measurements, %{conf: conf, changesets: changesets}, _config ->
        if conf.name == name, do: send(parent, {:insert_all, length(changesets)})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:started, id} = start!(5, insert_batch: 2)

    assert_received {:insert_all, 2}
    assert_received {:insert_all, 2}
    assert_received {:insert_all, 1}
    refute_received {:insert_all, _}

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker = 'Dawarich.Tracks.ChunkWorker' " <>
               "AND args->>'generation_id' = $1",
             [id]
           ) == [[5]]
  end
end
