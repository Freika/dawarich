defmodule Dawarich.Cable.PgBusTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Cable.{Bus, PgBus, PgStore}

  setup do
    cable = Application.get_env(:dawarich, :cable)
    prefix = Application.get_env(:dawarich, :cable_prefix)
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo, polling: false)

    on_exit(fn ->
      Application.put_env(:dawarich, :cable, cable)
      Application.put_env(:dawarich, :cable_prefix, prefix)
      :persistent_term.erase({Bus, :prefix})
    end)

    :ok
  end

  test "subscription acknowledges its committed fence before any eligible message" do
    for prefix <- [nil, "pg_fence"] do
      Application.put_env(:dawarich, :cable_prefix, prefix)
      :persistent_term.erase({Bus, :prefix})
      [spec] = Bus.child_specs()
      start_supervised!(spec)
      namespace = prefix || ""
      broadcasting = "points"
      assert Bus.channel(broadcasting) == if(prefix, do: prefix <> ":points", else: "points")

      assert {:ok, 1} = PgStore.append(ScratchRepo, namespace, broadcasting, "old")
      assert {:ok, ref} = Bus.subscribe(broadcasting)
      assert_receive {:cable_pg, _, ^namespace, :subscribed, ^broadcasting, ^ref} = ack
      assert Bus.event(ack) == {:subscribed, broadcasting}

      assert {:ok, 2} = PgStore.append(ScratchRepo, namespace, broadcasting, "new")
      send(Bus, :poll)
      :sys.get_state(Bus)

      assert_receive {:cable_pg, _, ^namespace, ^broadcasting, 1, "old"} = old
      assert Bus.event(old) == :ignore
      assert_receive {:cable_pg, _, ^namespace, ^broadcasting, 2, "new"} = new
      assert Bus.event(new) == {:message, broadcasting, "new"}
      refute_received {:cable_pg, _, _, _, _, _}
      assert {:ok, _} = Bus.unsubscribe(broadcasting)
      stop_supervised!(Bus)
    end
  end

  test "bounded polling advances only dispatched rows and keeps the cursor on a read failure" do
    [spec] = Bus.child_specs()
    start_supervised!(spec)
    namespace = Bus.prefix() || ""
    assert {:ok, ref} = Bus.subscribe("points")
    assert_receive {:cable_pg, _, _, :subscribed, "points", ^ref} = ack
    assert Bus.event(ack) == {:subscribed, "points"}

    for seq <- 1..101 do
      assert {:ok, ^seq} =
               PgStore.append(ScratchRepo, namespace, "points", Integer.to_string(seq))
    end

    send(Bus, :poll)
    assert %{cursor: 100} = :sys.get_state(Bus)
    :sys.replace_state(Bus, &%{&1 | repo: Dawarich.NotStartedRepo})
    pid = Process.whereis(Bus)

    ExUnit.CaptureLog.capture_log(fn ->
      send(Bus, :poll)
      assert %{cursor: 100} = :sys.get_state(Bus)
      assert Process.whereis(Bus) == pid
    end)

    :sys.replace_state(Bus, &%{&1 | repo: ScratchRepo})
    send(Bus, :poll)
    assert %{cursor: 101, poll: 200} = :sys.get_state(Bus)

    for seq <- 1..101 do
      assert_receive {:cable_pg, _, _, "points", ^seq, payload} = message
      assert payload == Integer.to_string(seq)
      assert Bus.event(message) == {:message, "points", payload}
    end

    refute_received {:cable_pg, _, _, _, _, _}

    assert rows("SELECT count(*) FROM phoenix.cable_events WHERE observed_at IS NOT NULL") == [
             [101]
           ]
  end

  test "two independent pollers deliver every event once to their own subscribers" do
    parent = self()
    namespace = "fanout"
    payloads = [~s({ "v": "München" }), <<0, 255>>, "[1,\n 2]", "last"]

    nodes =
      for {server, pubsub} <- [
            {__MODULE__.First, __MODULE__.FirstPubSub},
            {__MODULE__.Second, __MODULE__.SecondPubSub}
          ] do
        start_supervised!(Supervisor.child_spec({Phoenix.PubSub, name: pubsub}, id: pubsub))

        opts = [
          name: server,
          repo: ScratchRepo,
          namespace: namespace,
          pubsub: pubsub,
          polling: false
        ]

        start_supervised!(Supervisor.child_spec({PgBus, opts}, id: server))
        subscription = [server: server, pubsub: pubsub, namespace: namespace]

        subscriber =
          Task.async(fn ->
            {:ok, ref} = PgBus.subscribe("points", subscription)
            assert_receive {:cable_pg, ^pubsub, ^namespace, :subscribed, "points", ^ref} = ack
            assert Bus.event(ack) == {:subscribed, "points"}
            send(parent, {:ready, self()})

            heard =
              for {payload, seq} <- Enum.with_index(payloads, 1) do
                assert_receive {:cable_pg, ^pubsub, ^namespace, "points", ^seq, ^payload} = event,
                               1_000

                assert Bus.event(event) == {:message, "points", payload}
                payload
              end

            send(parent, {:complete, self()})
            assert_receive :finish, 1_000
            refute_received {:cable_pg, _, _, _, _, _}
            {:ok, _} = PgBus.unsubscribe("points", subscription)
            heard
          end)

        assert_receive {:ready, pid}, 1_000
        assert pid == subscriber.pid
        {server, subscriber}
      end

    for {payload, seq} <- Enum.with_index(payloads, 1) do
      publisher = Task.async(fn -> PgStore.append(ScratchRepo, namespace, "points", payload) end)
      assert Task.await(publisher) == {:ok, seq}
      ordered = if rem(seq, 2) == 0, do: Enum.reverse(nodes), else: nodes

      for {server, _} <- ordered do
        send(server, :poll)
        assert %{cursor: ^seq} = :sys.get_state(server)
      end
    end

    for {server, subscriber} <- nodes do
      pid = subscriber.pid
      assert_receive {:complete, ^pid}, 1_000
      send(server, :poll)
      :sys.get_state(server)
      send(pid, :finish)
      assert Task.await(subscriber) == payloads
    end

    assert rows("SELECT count(*) FROM phoenix.cable_events WHERE observed_at IS NOT NULL") == [
             [4]
           ]
  end
end
