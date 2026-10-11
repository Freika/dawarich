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

  test "native map Family delivery invalidates only an admitted enabled membership", %{
    scope: scope,
    socket: socket
  } do
    family!()
    family_layer!(true)
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    topic = RailsMessages.broadcasting(["family_locations", {:family, 881_401}])
    assert_receive {:native_subscribe, ^topic}
    message = {:native_message, topic, "synthetic-family-update"}
    assert {:delivered, socket} = Subscriptions.deliver(socket, message)

    assert hd(socket.private.live_temp.push_events) == [
             "map:invalidate",
             %{kind: "family", revision: 1}
           ]

    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [881_401])
    assert {:ignored, socket} = Subscriptions.deliver(socket, message)
    assert_receive {:native_unsubscribe, ^topic}
    refute Map.has_key?(socket.assigns.native_subscriptions.topics, topic)

    assert Map.has_key?(
             socket.assigns.native_subscriptions.topics,
             RailsMessages.broadcasting(["points", {:user, 881_401}])
           )

    assert hd(socket.private.live_temp.push_events) == [
             "map:invalidate",
             %{kind: "reconnect", revision: 2}
           ]

    refute inspect(socket.assigns.native_subscriptions) =~ "synthetic-family-update"
    Subscriptions.release(socket)
  end

  test "native map Family preference changes reconcile one listener and release it", %{
    scope: scope,
    socket: socket
  } do
    family!()
    descriptor = %{kind: :map, scope: scope}
    topic = RailsMessages.broadcasting(["family_locations", {:family, 881_401}])
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    refute Map.has_key?(socket.assigns.native_subscriptions.topics, topic)
    family_layer!(true)
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    assert_receive {:native_subscribe, ^topic}
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    refute_receive {:native_subscribe, ^topic}
    family_layer!(false)
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    assert_receive {:native_unsubscribe, ^topic}
    refute Map.has_key?(socket.assigns.native_subscriptions.topics, topic)

    assert hd(socket.private.live_temp.push_events) == [
             "map:invalidate",
             %{kind: "reconnect", revision: 1}
           ]

    Subscriptions.release(socket)
  end

  test "native host layer saves synchronize the current Family subscription", %{
    scope: scope,
    socket: socket
  } do
    family!()
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)

    socket =
      Phoenix.Component.assign(socket,
        map_settings: %{saved: %{}, draft_modes: nil, error: nil, notice: nil},
        page: nil,
        map_config: %{},
        map_url: %{"panel" => "layers"}
      )

    {:noreply, socket} =
      DawarichWeb.MapLive.Native.handle_event(
        "settings:map_layers",
        %{"layers" => ["Points", "Family Members"]},
        socket
      )

    topic = RailsMessages.broadcasting(["family_locations", {:family, 881_401}])
    assert_receive {:native_subscribe, ^topic}
    assert socket.assigns.map_config["familyEnabled"] == true

    {:noreply, socket} =
      DawarichWeb.MapLive.Native.handle_event(
        "settings:map_layers",
        %{"layers" => ["Points"]},
        socket
      )

    assert_receive {:native_unsubscribe, ^topic}
    refute Map.has_key?(socket.assigns.native_subscriptions.topics, topic)
    Subscriptions.release(socket)
  end

  defp family! do
    at = NaiveDateTime.utc_now()

    Repo.insert_all("families", [
      %{
        id: 881_401,
        creator_id: 881_401,
        name: "Native map family",
        created_at: at,
        updated_at: at
      }
    ])

    Repo.insert_all("family_memberships", [
      %{
        id: 881_401,
        family_id: 881_401,
        user_id: 881_401,
        role: 0,
        created_at: at,
        updated_at: at
      }
    ])
  end

  defp family_layer!(enabled) do
    layers = if enabled, do: ["Points", "Family Members"], else: ["Points"]

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings, '{enabled_map_layers}', $2) WHERE id=$1",
      [881_401, layers]
    )
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

  test "large legacy batches still deliver only a bounded native invalidation", %{
    scope: scope,
    socket: socket
  } do
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    topic = RailsMessages.broadcasting(["map_edits", {:user, 881_401}])
    payload = :binary.copy("legacy-edit", 7000)
    assert {:delivered, socket} = Subscriptions.deliver(socket, {:native_message, topic, payload})
    ["map:invalidate", receipt] = hd(socket.private.live_temp.push_events)
    assert receipt == %{kind: "map_edits", revision: 1}
    refute inspect(socket.assigns.native_subscriptions) =~ "legacy-edit"
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

  test "native live mode preference releases only point delivery and resubscribes once", %{
    scope: scope,
    socket: socket
  } do
    descriptor = %{kind: :map, scope: scope}
    point_topic = RailsMessages.broadcasting(["points", {:user, 881_401}])
    track_topic = RailsMessages.broadcasting(["tracks", {:user, 881_401}])
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    assert_receive {:native_subscribe, ^point_topic}

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings, '{live_map_enabled}', 'false') WHERE id=$1",
      [881_401]
    )

    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    assert_receive {:native_unsubscribe, ^point_topic}
    refute Map.has_key?(socket.assigns.native_subscriptions.topics, point_topic)
    assert Map.has_key?(socket.assigns.native_subscriptions.topics, track_topic)

    assert {:ignored, socket} =
             Subscriptions.deliver(socket, {:native_message, point_topic, "synthetic-point"})

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings, '{live_map_enabled}', 'true') WHERE id=$1",
      [881_401]
    )

    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    assert_receive {:native_subscribe, ^point_topic}
    socket = Subscriptions.sync(socket, descriptor, bus: NativeMapBus)
    refute_receive {:native_subscribe, ^point_topic}

    assert {:delivered, socket} =
             Subscriptions.deliver(socket, {:native_message, point_topic, "synthetic-point"})

    Subscriptions.release(socket)
  end
end
