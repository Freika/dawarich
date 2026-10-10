defmodule DawarichWeb.NativeMapDeliveryTest do
  use ExUnit.Case, async: true
  alias Dawarich.{Repo, Accounts, Maps, RailsMessages}
  alias DawarichWeb.MapLive.Subscriptions
  alias Dawarich.Test.{TripsSeeds, NativeMapBus}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    TripsSeeds.user!(881_401)
    scope = Maps.principal(Accounts.get(881_401), "de")

    socket = %Phoenix.LiveView.Socket{
      transport_pid: self(),
      private: %{live_temp: %{}},
      assigns: %{__changed__: %{}, current_scope: scope}
    }

    %{scope: scope, socket: socket}
  end

  test "permission loss between queued event and delivery releases subscription without data", %{
    scope: scope,
    socket: socket
  } do
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    topic = RailsMessages.broadcasting(["points", {:user, 881_401}])
    assert_receive {:native_subscribe, ^topic}
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [881_401])

    assert {:refused, socket} =
             Subscriptions.deliver(socket, {:native_message, topic, "[52,13,80,10,123,9,1,\"\"]"})

    assert socket.assigns.native_subscriptions.topics == %{}
    assert_receive {:native_unsubscribe, ^topic}
    assert hd(socket.private.live_temp[:push_events]) == ["map:clear", %{code: "stale_session"}]
    refute inspect(socket.assigns) =~ "[52,13"
  end

  test "reconnect refreshes revision without replaying duplicate edits", %{
    scope: scope,
    socket: socket
  } do
    descriptor = %{kind: :map, scope: scope}
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    topic = RailsMessages.broadcasting(["map_edits", {:user, 881_401}])
    assert_receive {:native_subscribe, ^topic}
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    refute_receive {:native_subscribe, ^topic}
    message = {:native_message, topic, ~s({"action":"delete","point_ids":[7,8]})}
    assert {:delivered, socket} = Subscriptions.deliver(socket, message)
    revision = socket.assigns.native_subscriptions.revision
    assert {:ignored, _} = Subscriptions.deliver(socket, message)
    socket = Subscriptions.reconnect(socket)
    assert socket.assigns.native_subscriptions.revision == revision + 1
    assert {:ignored, socket} = Subscriptions.deliver(socket, message)
    ["map:invalidate", receipt] = hd(socket.private.live_temp.push_events)
    assert Map.keys(receipt) |> Enum.sort() == [:kind, :revision]
    assert receipt.kind == "reconnect"
    refute inspect(socket.assigns.native_subscriptions) =~ "point_ids"
    Subscriptions.release(socket)
  end

  test "disconnected mount and unrelated streams never allocate or deliver", %{
    scope: scope,
    socket: socket
  } do
    descriptor = %{kind: :map, scope: scope}
    static = Subscriptions.sync(%{socket | transport_pid: nil}, descriptor, bus: NativeMapBus)
    assert static.assigns.native_subscriptions.topics == %{}
    refute_receive {:native_subscribe, _}
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    assert {:ignored, _} = Subscriptions.deliver(socket, {:native_message, "foreign", "private"})
    Subscriptions.release(socket)
  end
end
