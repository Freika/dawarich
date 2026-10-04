defmodule Dawarich.Cable.PgTurboEventsTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Cable.{Bus, PgStore, TurboEvents}
  alias Dawarich.{Repo, ScratchCaseRepo}
  alias Dawarich.Test.{A12a, ParityHTML}

  defmodule RecordingStore do
    def append(repo, namespace, channel, payload) do
      owner = Process.get(:pg_cable_observer)
      if owner, do: send(owner, {:before_append, self(), channel, payload})
      count = Process.get(:pg_cable_count, 0) + 1
      if count == Process.get(:pg_cable_fail_at), do: raise("injected append failure")
      result = PgStore.append(repo, namespace, channel, payload)
      Process.put(:pg_cable_count, count)

      if owner && count == 2 do
        send(owner, {:pending, self()})

        receive do
          :commit -> :ok
          :rollback -> repo.rollback(:undo)
        end
      end

      result
    end
  end

  setup do
    reset!(ScratchCaseRepo)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    A12a.seed!()
    cable = Application.get_env(:dawarich, :cable)
    jobs = Application.get_env(:dawarich, :jobs_repo)

    Application.put_env(:dawarich, :cable,
      transport: :pg,
      pg_store: RecordingStore,
      repo: ScratchRepo,
      polling: false
    )

    Application.put_env(:dawarich, :jobs_repo, ScratchCaseRepo)

    on_exit(fn ->
      Application.put_env(:dawarich, :cable, cable)
      Application.put_env(:dawarich, :jobs_repo, jobs)
    end)

    :ok
  end

  test "notification claim and prepend plus badge events share one outer commit" do
    %{"events" => [%{"notification_id" => id}], "published" => rails} =
      A12a.relay!("notification_created")

    broadcasting = A12a.relay_broadcasting("notification_created")
    parent = self()

    for outcome <- [:commit, :rollback] do
      reset!(ScratchRepo)
      reset!(ScratchCaseRepo)
      [spec] = Bus.child_specs()
      start_supervised!(spec)
      {:ok, ref} = Bus.subscribe(broadcasting)
      assert_receive {:cable_pg, _, _, :subscribed, ^broadcasting, ^ref} = ack
      assert Bus.event(ack) == {:subscribed, broadcasting}
      rows("INSERT INTO phoenix.notification_events(notification_id) VALUES ($1)", [id])

      publisher =
        Task.async(fn ->
          Process.put(:pg_cable_observer, parent)

          result =
            try do
              TurboEvents.notifications(ScratchRepo, Repo)
            rescue
              error in MatchError ->
                if error.term == {:error, :undo},
                  do: :rolled_back,
                  else: reraise(error, __STACKTRACE__)
            end

          send(parent, {:finished, self(), result})
          result
        end)

      pid = publisher.pid

      try do
        receive do
          {:pending, ^pid} ->
            :ok

          {:finished, ^pid, _} ->
            assert other_events() == []
            flunk("claim returned without the append barrier")
        after
          1_000 -> flunk("claim did not reach the append barrier")
        end

        captured =
          for _ <- 1..2 do
            assert_receive {:before_append, ^pid, channel, payload}
            {channel, payload}
          end

        assert Enum.zip(rails, captured)
               |> Enum.all?(fn {{b, r}, {b2, p}} ->
                 b == b2 and same_stream?(r, p)
               end)

        assert other_events() == []
        assert rows("SELECT count(*) FROM phoenix.notification_events") == [[1]]
        assert rows("SELECT seq FROM phoenix.cable_events") == []
        send(pid, outcome)
        result = Task.await(publisher)
        assert_receive {:finished, ^pid, ^result}

        if outcome == :commit do
          assert result == 1
          assert rows("SELECT count(*) FROM phoenix.notification_events") == [[0]]

          assert rows("SELECT channel, payload FROM phoenix.cable_events ORDER BY seq") ==
                   Enum.map(captured, &Tuple.to_list/1)

          send(Bus, :poll)
          :sys.get_state(Bus)

          for {payload, seq} <- Enum.with_index(Enum.map(captured, &elem(&1, 1)), 1) do
            assert_receive {:cable_pg, _, _, ^broadcasting, ^seq, ^payload} = event
            assert Bus.event(event) == {:message, broadcasting, payload}
          end
        else
          assert result == :rolled_back
          assert rows("SELECT count(*) FROM phoenix.notification_events") == [[1]]
          assert rows("SELECT seq FROM phoenix.cable_events") == []
        end

        assert other_events() == []
      after
        send(pid, outcome)
      end

      {:ok, _} = Bus.unsubscribe(broadcasting)
      stop_supervised!(Bus)
    end
  end

  test "two relays claim each source once and an append failure leaves that source queued" do
    notification!()
    trip = A12a.trip_id!("trip_idle")

    rows(
      "INSERT INTO phoenix.trip_events(trip_id, kind, distance_unit, failed, created_at) VALUES ($1, 'path', 'km', false, now())",
      [trip]
    )

    Process.put(:pg_cable_fail_at, 2)

    try do
      assert_raise RuntimeError, "injected append failure", fn ->
        TurboEvents.notifications(ScratchRepo, Repo)
      end
    after
      Process.delete(:pg_cable_fail_at)
      Process.delete(:pg_cable_count)
    end

    assert rows("SELECT count(*) FROM phoenix.notification_events") == [[1]]
    assert rows("SELECT seq FROM phoenix.cable_events") == []
    assert other_events() == []
    parent = self()

    first =
      Task.async(fn ->
        Process.put(:pg_cable_observer, parent)
        TurboEvents.drain(ScratchRepo, Repo)
      end)

    first_pid = first.pid
    assert_receive {:pending, ^first_pid}, 1_000

    second =
      Task.async(fn ->
        Process.put(:pg_cable_observer, parent)
        TurboEvents.drain(ScratchRepo, Repo)
      end)

    second_pid = second.pid
    trip_broadcasting = A12a.relay_broadcasting("trip_path")

    try do
      assert_receive {:before_append, ^second_pid, ^trip_broadcasting, _}, 1_000
    after
      send(first_pid, :commit)
    end

    assert Task.await(first) + Task.await(second) == 2
    assert rows("SELECT count(*) FROM phoenix.notification_events") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.trip_events") == [[0]]
    assert rows("SELECT seq FROM phoenix.cable_events ORDER BY seq") == [[1], [2], [3]]
    assert TurboEvents.drain(ScratchRepo, Repo) == 0
    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[3]]
    assert other_events() == []
  end

  test "claimant death before commit retains source and rolls back both PG appends" do
    id = notification!()
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Process.put(:pg_cable_observer, parent)
        TurboEvents.notifications(ScratchRepo, Repo)
      end)

    assert_receive {:pending, ^pid}, 1_000
    captured = captured(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}

    assert {:ok, :settled} =
             ScratchRepo.transaction(fn ->
               assert [[^id]] =
                        rows(
                          "SELECT notification_id FROM phoenix.notification_events WHERE notification_id = $1 FOR UPDATE",
                          [id]
                        )

               assert rows("SELECT seq FROM phoenix.cable_events") == []
               :settled
             end)

    assert other_events() == []
    assert TurboEvents.notifications(ScratchRepo, Repo) == 1
    assert rows("SELECT count(*) FROM phoenix.notification_events") == [[0]]

    assert rows("SELECT channel, payload FROM phoenix.cable_events ORDER BY seq") ==
             Enum.map(captured, &Tuple.to_list/1)
  end

  test "publisher death after confirmed commit leaves one pair for a surviving poller" do
    notification!()
    broadcasting = A12a.relay_broadcasting("notification_created")
    [spec] = Bus.child_specs()
    start_supervised!(spec)
    {:ok, ref} = Bus.subscribe(broadcasting)
    assert_receive {:cable_pg, _, _, :subscribed, ^broadcasting, ^ref} = ack
    assert Bus.event(ack) == {:subscribed, broadcasting}
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Process.put(:pg_cable_observer, parent)
        count = TurboEvents.notifications(ScratchRepo, Repo)
        send(parent, {:committed, self(), count})
        receive(do: (:stop -> :ok))
      end)

    assert_receive {:pending, ^pid}, 1_000
    captured = captured(pid)
    send(pid, :commit)
    assert_receive {:committed, ^pid, 1}, 1_000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    assert rows("SELECT count(*) FROM phoenix.notification_events") == [[0]]
    send(Bus, :poll)
    :sys.get_state(Bus)

    for {{^broadcasting, payload}, seq} <- Enum.with_index(captured, 1) do
      assert_receive {:cable_pg, _, _, ^broadcasting, ^seq, ^payload} = event
      assert Bus.event(event) == {:message, broadcasting, payload}
    end

    send(Bus, :poll)
    :sys.get_state(Bus)
    refute_received {:cable_pg, _, _, _, _, _}
    assert rows("SELECT seq FROM phoenix.cable_events ORDER BY seq") == [[1], [2]]
    assert other_events() == []
  end

  defp notification! do
    [%{"notification_id" => id}] = A12a.relay!("notification_created")["events"]
    rows("INSERT INTO phoenix.notification_events(notification_id) VALUES ($1)", [id])
    id
  end

  defp captured(pid) do
    for _ <- 1..2 do
      assert_receive {:before_append, ^pid, channel, payload}
      {channel, payload}
    end
  end

  defp other_events,
    do: ScratchCaseRepo.query!("SELECT seq FROM phoenix.cable_events", [], log: false).rows

  defp same_stream?(rails, phoenix) do
    {r_wrap, r_html} = A12a.split_turbo(rails)
    {p_wrap, p_html} = A12a.split_turbo(phoenix)
    r_wrap == p_wrap and ParityHTML.normalize(r_html) == ParityHTML.normalize(p_html)
  end
end
