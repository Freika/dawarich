defmodule Dawarich.Cable.EventsRelayTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  alias Dawarich.Cable.EventsRelay
  alias Dawarich.Test.A12a

  setup context do
    if context[:auto_sandbox] do
      Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :auto)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual) end)
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    A12a.seed!()
    A12a.start_bus!()
    :ok
  end

  test "waits a second when idle and five after an error, an exit or a throw" do
    assert EventsRelay.next_delay(fn -> 0 end) == 1_000
    assert EventsRelay.next_delay(fn -> 3 end) == 0

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert EventsRelay.next_delay(fn -> raise DBConnection.ConnectionError, "down" end) ==
                 5_000
      end)

    assert log =~ "[Cable] events relay: DBConnection.ConnectionError"
    assert EventsRelay.next_delay(fn -> exit(:noproc) end) == 5_000
    assert EventsRelay.next_delay(fn -> throw(:gone) end) == 5_000
  end

  test "the relay drains on start, keeps polling, and loses nothing while the publisher is down" do
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})

    A12a.insert_events!(
      A12a.relay!("notification_created")["events"] ++ A12a.relay!("trip_path")["events"]
    )

    A12a.swap_publisher!(A12a.dead_redis_url())
    {:ok, _} = A12a.listen_all()
    relay = start_supervised!({EventsRelay, poll: 50, backoff: 50})
    :sys.get_state(relay)
    assert A12a.queued() == 2

    A12a.swap_publisher!(A12a.test_redis_url())
    for _ <- 1..3, do: assert({_, _} = A12a.heard())
    :sys.get_state(relay)
    assert A12a.queued() == 0

    A12a.insert_events!(A12a.relay!("trip_path")["events"])
    assert {_, _} = A12a.heard()
    assert A12a.heard_count(300) == 0
  end

  test "repeated relay crashes never reach the application supervisor; the endpoint keeps serving" do
    top = Process.whereis(Dawarich.Supervisor)

    {:ok, sup} =
      Supervisor.start_child(Dawarich.Supervisor, EventsRelay.supervisor_spec(poll: 60_000))

    on_exit(fn ->
      Supervisor.terminate_child(Dawarich.Supervisor, EventsRelay.Supervisor)
      Supervisor.delete_child(Dawarich.Supervisor, EventsRelay.Supervisor)
    end)

    for _ <- 1..10 do
      [{_, relay, _, _}] = Supervisor.which_children(sup)
      ref = Process.monitor(relay)
      Process.exit(relay, :kill)
      assert_receive {:DOWN, ^ref, :process, _, _}
    end

    assert Process.whereis(Dawarich.Supervisor) == top

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    client = Dawarich.Test.RawHTTP.connect(port)
    Dawarich.Test.RawHTTP.send_raw(client, "GET /notifications HTTP/1.1\r\nHost: a\r\n\r\n")
    assert {302, _headers, _body} = Dawarich.Test.RawHTTP.read_response(client)
  end

  @tag :auto_sandbox
  test "two relays never publish one event twice" do
    A12a.insert_events!(A12a.many_notification_events(150))
    {:ok, _} = A12a.listen_all()
    tasks = for _ <- 1..2, do: Task.async(fn -> A12a.drain_until_empty() end)
    assert tasks |> Enum.map(&Task.await(&1, 10_000)) |> Enum.sum() == 150
    assert A12a.heard_count(300) == 300
  end
end
