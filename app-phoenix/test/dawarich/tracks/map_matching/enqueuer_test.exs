Code.require_file("support.exs", __DIR__)

defmodule Dawarich.Tracks.MapMatching.EnqueuerTest do
  use Dawarich.TracksCase, async: false
  alias Dawarich.Tracks.MapMatching.{Enqueuer, State, Worker}
  alias Dawarich.MapMatching.{Fingerprint, Input, TestSupport}

  setup do
    TestSupport.setup!()
  end

  test "claim and Oban insert commit together; an insert failure rolls the claim back" do
    track = TestSupport.input!(ScratchRepo)
    before = State.read(ScratchRepo, track.id)
    TestSupport.fail_insert!(ScratchRepo)
    assert :error = Enqueuer.call(ScratchRepo, track.id)
    failed = State.read(ScratchRepo, track.id)
    assert failed.status == before.status
    assert failed.matched_path == nil
    assert failed.digest == Fingerprint.call(Input.load(ScratchRepo, track.id))
    assert failed.data == %{"enqueue_failed" => true}
    assert TestSupport.jobs(ScratchRepo, track.id) == []

    assert {:ok, :operation_survived} =
             ScratchRepo.transaction(fn ->
               assert :error = Enqueuer.call(ScratchRepo, track.id)
               assert ScratchRepo.query!("SELECT 1", [], log: false).rows == [[1]]
               :operation_survived
             end)

    assert State.read(ScratchRepo, track.id) == failed

    ScratchRepo.query!("ALTER TABLE oban.oban_jobs DROP CONSTRAINT mm_insert_probe", [],
      log: false
    )

    assert :enqueued = Enqueuer.call(ScratchRepo, track.id)
    assert State.read(ScratchRepo, track.id).status == :pending
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1
  end

  test "digest is computed under the row lock: a concurrent input change between read and claim cannot publish a stale digest" do
    track = TestSupport.input!(ScratchRepo)
    parent = self()

    locker =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SELECT id FROM tracks WHERE id=$1 FOR UPDATE", [track.id],
            log: false
          )

          send(parent, :locked)

          receive do
            :change -> :ok
          end

          ScratchRepo.query!("UPDATE points SET accuracy=42 WHERE track_id=$1", [track.id],
            log: false
          )
        end)
      end)

    assert_receive :locked
    claimer = Task.async(fn -> Enqueuer.call(ScratchRepo, track.id) end)
    wait_for_lock!()
    send(locker.pid, :change)
    Task.await(locker)
    assert :enqueued = Task.await(claimer)

    assert State.read(ScratchRepo, track.id).digest ==
             Fingerprint.call(Input.load(ScratchRepo, track.id))
  end

  test "skipped is written under the lock and is idempotent" do
    track = TestSupport.input!(ScratchRepo, eligible: false)
    assert :skip = Enqueuer.call(ScratchRepo, track.id)
    before = State.read(ScratchRepo, track.id)
    assert before.status == :skipped
    assert :skip = Enqueuer.call(ScratchRepo, track.id)
    assert State.read(ScratchRepo, track.id) == before
    assert TestSupport.jobs(ScratchRepo, track.id) == []
  end

  test "disabled enqueue leaves state untouched; re-enable invalidates old input before claiming" do
    track = TestSupport.input!(ScratchRepo)
    digest = Fingerprint.call(Input.load(ScratchRepo, track.id))

    State.write!(ScratchRepo, track.id, %{
      status: :matched,
      digest: digest,
      matched_path: %Geo.MultiLineString{
        coordinates: [[{13.0, 52.0}, {13.001, 52.0}]],
        srid: 4326
      }
    })

    before = State.read(ScratchRepo, track.id)
    System.put_env("MAP_MATCHING_ENABLED", "false")
    ScratchRepo.query!("UPDATE points SET accuracy=43 WHERE track_id=$1", [track.id], log: false)
    assert :disabled = Enqueuer.call(ScratchRepo, track.id)
    assert State.read(ScratchRepo, track.id) == before
    assert TestSupport.jobs(ScratchRepo, track.id) == []
    System.put_env("MAP_MATCHING_ENABLED", "true")
    assert :enqueued = Enqueuer.call(ScratchRepo, track.id)
    assert State.read(ScratchRepo, track.id).status == :pending
    assert State.read(ScratchRepo, track.id).matched_path == nil
    refute State.read(ScratchRepo, track.id).digest == digest
  end

  test "unique job per track+digest" do
    track = TestSupport.input!(ScratchRepo)
    assert :enqueued = Enqueuer.call(ScratchRepo, track.id)
    assert :current = Enqueuer.call(ScratchRepo, track.id)
    TestSupport.stale!(ScratchRepo, track.id)
    assert :enqueued = Enqueuer.call(ScratchRepo, track.id)
    assert [args] = TestSupport.jobs(ScratchRepo, track.id)
    assert {:ok, %{conflict?: true}} = Oban.insert(oban(), Worker.new(args))
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1
    ScratchRepo.query!("UPDATE points SET accuracy=44 WHERE track_id=$1", [track.id], log: false)
    assert :enqueued = Enqueuer.call(ScratchRepo, track.id)
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 2
  end

  test "disabled and demo tracks never enqueue or call Atlas" do
    track = TestSupport.input!(ScratchRepo)

    Application.put_env(:dawarich, :map_matching_client, fn _, _ ->
      flunk("Atlas called while disabled")
    end)

    System.delete_env("MAP_MATCHING_ENABLED")
    assert :disabled = Enqueuer.call(ScratchRepo, track.id)

    assert :ok =
             Worker.run(ScratchRepo, %Oban.Job{
               args: %{
                 "track_id" => track.id,
                 "digest" => State.read(ScratchRepo, track.id).digest
               }
             })

    assert TestSupport.jobs(ScratchRepo, track.id) == []
    System.put_env("MAP_MATCHING_ENABLED", "true")
    ScratchRepo.query!("UPDATE tracks SET demo=true WHERE id=$1", [track.id], log: false)
    assert :skip = Enqueuer.call(ScratchRepo, track.id)
    assert TestSupport.jobs(ScratchRepo, track.id) == []
  end

  defp wait_for_lock!(remaining \\ 1000)
  defp wait_for_lock!(0), do: flunk("claimer did not wait for track lock")

  defp wait_for_lock!(remaining) do
    waiting =
      ScratchRepo.query!(
        "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%tracks%'",
        [],
        log: false
      ).rows

    if waiting == [[0]] do
      Process.sleep(5)
      wait_for_lock!(remaining - 1)
    end
  end
end
