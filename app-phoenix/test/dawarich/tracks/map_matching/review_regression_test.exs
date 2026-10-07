Code.require_file("support.exs", __DIR__)

defmodule Dawarich.Tracks.MapMatching.ReviewRegressionTest do
  use Dawarich.TracksCase, async: false
  alias Dawarich.MapMatching.{Fingerprint, Input, TestSupport}
  alias Dawarich.MapMatching.Atlas.Client.Error
  alias Dawarich.Tracks.{Builder, Reprocessor, Store}
  alias Dawarich.Tracks.MapMatching.{Enqueuer, State, Sweeper, Worker}

  setup do
    TestSupport.setup!()
  end

  test "F1 default OFF hook adds zero caller queries and leaves track input and state untouched" do
    track = TestSupport.input!(ScratchRepo)
    System.delete_env("MAP_MATCHING_ENABLED")
    before = State.read(ScratchRepo, track.id)
    stored = Store.get(ScratchRepo, track.id)

    baseline =
      queries(fn ->
        Reprocessor.reprocess!(ScratchRepo, track.user, stored, nil,
          detector: fn _, _, _ -> [] end,
          map_matching: false
        )
      end)

    hooked =
      queries(fn ->
        Reprocessor.reprocess!(ScratchRepo, track.user, stored, nil,
          detector: fn _, _, _ -> [] end
        )
      end)

    TestSupport.await_hooks!()
    assert length(hooked) - length(baseline) == 0
    assert State.read(ScratchRepo, track.id) == before
    assert TestSupport.jobs(ScratchRepo, track.id) == []
    System.put_env("MAP_MATCHING_ENABLED", "false")
    assert queries(fn -> assert :disabled = Enqueuer.call(ScratchRepo, track.id) end) == []

    stored_enabled = TestSupport.input!(ScratchRepo)
    System.delete_env("MAP_MATCHING_ENABLED")

    rows(
      "INSERT INTO instance_settings(key,value,created_at,updated_at) VALUES('map_matching_enabled','true'::jsonb,now(),now())"
    )

    assert queries(fn -> assert :deferred = Enqueuer.defer(ScratchRepo, stored_enabled.id) end) ==
             []

    TestSupport.await_hooks!()
    assert State.read(ScratchRepo, stored_enabled.id).status == :pending
    assert length(TestSupport.jobs(ScratchRepo, stored_enabled.id)) == 1
  end

  test "F2 completed builder returns while enabled enqueue waits on an independent row lock" do
    track = TestSupport.input!(ScratchRepo)
    parent = self()

    locker =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          rows("SELECT id FROM tracks WHERE id=$1 FOR UPDATE", [track.id])
          send(parent, :locked)
          receive do: (:release -> :ok)
        end)
      end)

    assert_receive :locked

    builder =
      Task.async(fn -> Builder.create_track!(ScratchRepo, track.user, track.points, 100) end)

    try do
      wait_lock!()
      assert {:ok, {:ok, %{id: id}}} = Task.yield(builder, 200)
      assert id == track.id
      assert TestSupport.jobs(ScratchRepo, track.id) == []
    after
      send(locker.pid, :release)
      Task.await(locker)
      if Process.alive?(builder.pid), do: Task.await(builder)
      TestSupport.await_hooks!()
    end

    assert [%{"track_id" => id}] = TestSupport.jobs(ScratchRepo, track.id)
    assert id == track.id

    for outcome <- [:rollback, :commit] do
      track = TestSupport.input!(ScratchRepo)
      parent = self()

      transaction =
        Task.async(fn ->
          ScratchRepo.transaction(fn ->
            rows("UPDATE points SET accuracy=61 WHERE track_id=$1", [track.id])

            assert queries(fn ->
                     assert :deferred = Enqueuer.defer(ScratchRepo, track.id)
                   end) == []

            send(parent, :hook_ready)
            receive do: (:finish -> :ok)
            if outcome == :rollback, do: ScratchRepo.rollback(:probe)
          end)
        end)

      try do
        assert_receive :hook_ready
        assert Task.Supervisor.children(Dawarich.Tracks.MapMatching.Tasks) != []
        assert TestSupport.jobs(ScratchRepo, track.id) == []
      after
        send(transaction.pid, :finish)
        Task.await(transaction)
        TestSupport.await_hooks!()
      end

      if outcome == :rollback do
        assert TestSupport.jobs(ScratchRepo, track.id) == []
        assert State.read(ScratchRepo, track.id).digest == nil
      else
        assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1

        assert State.read(ScratchRepo, track.id).digest ==
                 Fingerprint.call(Input.load(ScratchRepo, track.id))
      end
    end
  end

  test "F3 persistent real Oban 429 executions exhaust five total attempts including snoozes" do
    track = TestSupport.input!(ScratchRepo)
    assert :enqueued = Enqueuer.call(ScratchRepo, track.id)
    counter = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:dawarich, :map_matching_client, fn _, _ ->
      Agent.update(counter, &(&1 + 1))
      {:error, %Error{code: "capacity", status: 429, transient?: true, retry_after: 1}}
    end)

    for _ <- 1..6, do: Oban.drain_queue(oban(), queue: :map_matching, with_scheduled: true)
    assert State.read(ScratchRepo, track.id).status == :failed
    assert State.read(ScratchRepo, track.id).data["error"]["attempt"] == 5
    assert Agent.get(counter, & &1) == 5

    assert [["completed", %{"snoozed" => 4}]] =
             rows("SELECT state,meta FROM oban.oban_jobs WHERE worker=$1", [inspect(Worker)])
  end

  test "F4 failed job insertion preserves obsolete-result invalidation and sweeper recovery" do
    track = TestSupport.input!(ScratchRepo)
    digest = Fingerprint.call(Input.load(ScratchRepo, track.id))

    State.write!(ScratchRepo, track.id, %{
      status: :matched,
      digest: digest,
      matched_at: DateTime.utc_now(),
      matched_path: %Geo.MultiLineString{
        coordinates: [[{13.0, 52.0}, {13.001, 52.0}]],
        srid: 4326
      }
    })

    rows("UPDATE points SET accuracy=59 WHERE track_id=$1", [track.id])
    TestSupport.fail_insert!(ScratchRepo)

    assert {:ok, :survived} =
             ScratchRepo.transaction(fn ->
               assert :error = Enqueuer.call(ScratchRepo, track.id)
               assert rows("SELECT 1") == [[1]]
               :survived
             end)

    state = State.read(ScratchRepo, track.id)
    assert state.status == nil
    refute State.result?(state)
    assert state.matched_path == nil
    assert state.digest == Fingerprint.call(Input.load(ScratchRepo, track.id))
    assert TestSupport.jobs(ScratchRepo, track.id) == []
    rows("ALTER TABLE oban.oban_jobs DROP CONSTRAINT mm_insert_probe")
    assert :ok = Sweeper.run(ScratchRepo)
    assert State.read(ScratchRepo, track.id).status == :pending
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1
  end

  defp queries(fun) do
    handler = {__MODULE__, make_ref()}
    event = ScratchRepo.config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(handler, event, &__MODULE__.query/4, self())

    try do
      fun.()
      collect([])
    after
      :telemetry.detach(handler)
    end
  end

  def query(_, _, meta, caller) do
    if self() == caller, do: send(caller, {:sql, meta.query})
  end

  defp collect(acc) do
    receive do
      {:sql, sql} -> collect([sql | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp wait_lock!(remaining \\ 1000)
  defp wait_lock!(0), do: flunk("enqueue did not reach track lock")

  defp wait_lock!(remaining) do
    if rows(
         "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE 'SELECT demo FROM tracks%'"
       ) == [[0]] do
      Process.sleep(5)
      wait_lock!(remaining - 1)
    end
  end
end
