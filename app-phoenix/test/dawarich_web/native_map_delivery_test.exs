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

  test "native family invalidations consume the real M4 consent producer", %{
    scope: scope,
    socket: socket
  } do
    family!()
    family_layer!(true)
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope})
    :ok = Dawarich.Families.Events.broadcast(scope.user.id, :consent)
    assert_receive {:domain_changed, 881_401, :consent} = message
    assert {:delivered, socket} = Subscriptions.deliver(socket, message)

    assert hd(socket.private.live_temp.push_events) == [
             "map:invalidate",
             %{kind: "family", revision: 1}
           ]

    Subscriptions.release(socket)
  end

  test "a Family topic the chrome already watches is delivered once and survives release", %{
    scope: scope,
    socket: socket
  } do
    family!()
    family_layer!(true)
    :ok = Phoenix.PubSub.subscribe(Dawarich.PubSub, "family:user:881401")
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope})
    :ok = Dawarich.Families.Events.broadcast(scope.user.id, :consent)
    assert_receive {:domain_changed, 881_401, :consent}
    refute_receive {:domain_changed, 881_401, :consent}, 50
    Subscriptions.release(socket)
    :ok = Dawarich.Families.Events.broadcast(scope.user.id, :consent)
    assert_receive {:domain_changed, 881_401, :consent}
  end

  test "native map Family delivery invalidates only an admitted enabled membership", %{
    scope: scope,
    socket: socket
  } do
    family!()
    family_layer!(true)
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    topic = "family:user:881401"
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
    topic = "family:user:881401"
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
        page: %{family: true, airtrail: false},
        map_config: %{},
        map_url: %{"panel" => "layers"}
      )

    {:noreply, socket} =
      DawarichWeb.MapLive.Native.handle_event(
        "settings:family_layer",
        %{"enabled" => "true"},
        socket
      )

    topic = "family:user:881401"
    assert_receive {:native_subscribe, ^topic}
    assert socket.assigns.map_config["familyEnabled"] == true

    {:noreply, socket} =
      DawarichWeb.MapLive.Native.handle_event(
        "settings:family_layer",
        %{"enabled" => "false"},
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
    socket =
      Subscriptions.sync(socket, %{kind: :map, scope: scope},
        bus: NativeMapBus,
        admission_ttl_ms: 0
      )

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

  test "the map reuses one admission for every message inside the window", %{
    scope: scope,
    socket: socket
  } do
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    topic = RailsMessages.broadcasting(["tracks", {:user, 881_401}])

    reads =
      queries(fn ->
        Enum.reduce(1..100, socket, fn n, socket ->
          assert {:delivered, socket} =
                   Subscriptions.deliver(socket, {:native_message, topic, "track-#{n}"})

          socket
        end)
      end)

    assert reads == []
    Subscriptions.release(socket)
  end

  test "a revoked map session is refused on the first message after the window", %{
    scope: scope,
    socket: socket
  } do
    socket =
      Subscriptions.sync(socket, %{kind: :map, scope: scope},
        bus: NativeMapBus,
        admission_ttl_ms: 40
      )

    topic = RailsMessages.broadcasting(["tracks", {:user, 881_401}])
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [881_401])
    assert {:delivered, socket} = Subscriptions.deliver(socket, {:native_message, topic, "a"})
    Process.sleep(50)
    assert {:refused, socket} = Subscriptions.deliver(socket, {:native_message, topic, "b"})
    assert hd(socket.private.live_temp[:push_events]) == ["map:clear", %{code: "stale_session"}]
  end

  test "Family domain messages re-admit inside the map window", %{
    scope: scope,
    socket: socket
  } do
    family!()
    family_layer!(true)
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    topic = "family:user:881401"
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [881_401])

    assert {:ignored, socket} =
             Subscriptions.deliver(socket, {:native_message, topic, "synthetic-family-update"})

    refute Map.has_key?(socket.assigns.native_subscriptions.topics, topic)
  end

  test "a live point outside the map's date range refreshes nothing, as on Rails", %{
    scope: scope,
    socket: socket
  } do
    range = %{startAt: "2026-10-16T00:00:00+02:00", endAt: "2026-10-18T00:00:00+02:00"}
    socket = %{socket | assigns: Map.put(socket.assigns, :map_range, range)}
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    topic = RailsMessages.broadcasting(["points", {:user, 881_401}])
    point = fn time -> Jason.encode!([52.5, 13.4, 90, 35, time, 1.4, 900, "Germany"]) end
    inside = DateTime.to_unix(~U[2026-10-17 10:00:00Z])
    early = DateTime.to_unix(~U[2026-10-15 10:00:00Z])
    late = DateTime.to_unix(~U[2026-10-18 10:00:00Z])

    assert {:ignored, socket} =
             Subscriptions.deliver(socket, {:native_message, topic, point.(early)})

    assert {:ignored, socket} =
             Subscriptions.deliver(socket, {:native_message, topic, point.(late)})

    assert {:delivered, _} =
             Subscriptions.deliver(socket, {:native_message, topic, point.(inside)})
  end

  test "a range reaching now keeps its end open for live points", %{scope: scope, socket: socket} do
    now = DateTime.utc_now()

    range = %{
      startAt: DateTime.to_iso8601(DateTime.add(now, -3600)),
      endAt: DateTime.to_iso8601(DateTime.add(now, 60))
    }

    socket = %{socket | assigns: Map.put(socket.assigns, :map_range, range)}
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    topic = RailsMessages.broadcasting(["points", {:user, 881_401}])
    later = DateTime.to_unix(DateTime.add(now, 600))
    payload = Jason.encode!([52.5, 13.4, 90, 35, later, 1.4, 901, "Germany"])
    assert {:delivered, _} = Subscriptions.deliver(socket, {:native_message, topic, payload})
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

  test "the map listens only to the streams the Rails map listens to", %{
    scope: scope,
    socket: socket
  } do
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope}, bus: NativeMapBus)
    kinds = socket.assigns.native_subscriptions.topics |> Map.keys() |> Enum.sort()

    assert kinds ==
             Enum.sort(
               for(
                 stream <- ~w(points tracks map_edits),
                 do: RailsMessages.broadcasting([stream, {:user, 881_401}])
               )
             )

    for kind <- [:imports, :notifications, :sharing] do
      message = {:domain_changed, 881_401, kind}
      assert {:ignored, _} = Subscriptions.deliver(socket, message)
    end

    assert socket.private.live_temp[:push_events] in [nil, []]
    Subscriptions.release(socket)
  end

  test "a domain message for a topic the map does not hold costs no admission", %{
    scope: scope,
    socket: socket
  } do
    socket = Subscriptions.sync(socket, %{kind: :map, scope: scope})

    assert queries(fn ->
             assert {:ignored, _} =
                      Subscriptions.deliver(socket, {:domain_changed, 881_401, :notifications})
           end) == []

    Subscriptions.release(socket)
  end

  defp queries(fun) do
    owner = self()
    key = {__MODULE__, make_ref()}

    :telemetry.attach(
      key,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ -> if self() == owner, do: send(owner, {key, metadata.query}) end,
      nil
    )

    try do
      fun.()
      collect(key, [])
    after
      :telemetry.detach(key)
    end
  end

  defp collect(key, acc) do
    receive do
      {^key, query} -> collect(key, [query | acc])
    after
      0 -> Enum.reverse(acc)
    end
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
