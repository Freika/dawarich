defmodule Dawarich.Cable.EventsRelayTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  alias Dawarich.Cable.EventsRelay
  alias Dawarich.Test.A12a

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    A12a.seed!()
    A12a.start_bus!()
    :ok
  end

  test "claims in id order, waits a second when idle and five after an error" do
    assert EventsRelay.next_delay(fn -> 0 end) == 1_000
    assert EventsRelay.next_delay(fn -> 3 end) == 0

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert EventsRelay.next_delay(fn -> raise DBConnection.ConnectionError, "down" end) ==
                 5_000
      end)

    assert log =~ "[Cable] events relay: DBConnection.ConnectionError"
  end

  test "two relays never publish one event twice" do
    A12a.insert_events!(A12a.many_notification_events(150))
    {:ok, _} = A12a.listen_all()
    tasks = for _ <- 1..2, do: Task.async(fn -> A12a.drain_until_empty() end)
    assert tasks |> Enum.map(&Task.await(&1, 10_000)) |> Enum.sum() == 150
    assert A12a.heard_count(300) == 300
  end
end
