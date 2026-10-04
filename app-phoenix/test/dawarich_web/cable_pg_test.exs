defmodule DawarichWeb.CablePgTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Cable.{Bus, Frames, PgStore}
  alias Dawarich.ScratchRepo
  alias Dawarich.Test.A12a

  setup do
    Dawarich.JobsCase.reset!(ScratchRepo)
    A12a.seed!()
    cable = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo, polling: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, cable) end)
    [spec] = Bus.child_specs()
    start_supervised!(spec)
    {:ok, port: A12a.serve_cable!()}
  end

  test "alias subscription preserves an active broadcasting fence and delivery after alias removal",
       %{port: port} do
    recorded = A12a.case!("points_alias")["steps"]

    ids =
      for %{"send" => text} <- recorded,
          %{"command" => "subscribe", "identifier" => id} <- [Jason.decode!(text)],
          do: id

    [first, other] = ids

    confirmations =
      for %{"expect" => frame} <- recorded, frame =~ "confirm_subscription", do: frame

    messages =
      for %{"expect" => frame} <- recorded,
          Map.has_key?(Jason.decode!(frame), "message"),
          do: frame

    payloads = for %{"publish" => publication} <- recorded, do: publication["payload"]
    [both, remaining] = payloads
    broadcasting = A12a.broadcasting("points", "alice")
    namespace = Bus.prefix() || ""
    socket = A12a.open!(port, A12a.cookie("alice"))
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert A12a.next_frame(socket) == %{"expect" => Frames.welcome()}

    subscribe(socket, first)
    assert A12a.next_frame(socket) == %{"expect" => Enum.at(confirmations, 0)}
    assert {:ok, 1} = PgStore.append(ScratchRepo, namespace, broadcasting, both)
    subscribe(socket, other)
    assert A12a.next_frame(socket) == %{"expect" => Enum.at(confirmations, 1)}
    poll()
    delivered = for _ <- 1..2, do: A12a.next_frame(socket)["expect"]
    assert Enum.sort(delivered) == Enum.sort(Enum.take(messages, 2))

    A12a.send_text(socket, Jason.encode!(%{command: "unsubscribe", identifier: other}))
    barrier = ~s({"channel":"FamilyLocationsChannel"})
    subscribe(socket, barrier)
    assert A12a.next_frame(socket) == %{"expect" => Frames.reject(barrier)}
    assert {:ok, 2} = PgStore.append(ScratchRepo, namespace, broadcasting, remaining)
    poll()
    assert A12a.next_frame(socket) == %{"expect" => Enum.at(messages, 2)}

    A12a.send_text(socket, Jason.encode!(%{command: "unsubscribe", identifier: first}))

    assert {:ok, 3} =
             PgStore.append(ScratchRepo, namespace, broadcasting, "\"before fresh fence\"")

    subscribe(socket, first)
    assert A12a.next_frame(socket) == %{"expect" => Frames.confirm(first)}
    assert {:ok, 4} = PgStore.append(ScratchRepo, namespace, broadcasting, "\"fresh\"")
    poll()
    assert A12a.next_frame(socket) == %{"expect" => Frames.message(first, "\"fresh\"")}
    assert A12a.next_frame(socket, 100) == %{"error" => ":timeout"}
  end

  test "PG sockets confirm after subscription readiness and deliver exact ActionCable frames",
       %{port: port} do
    id = ~s({"channel":"PointsChannel"})
    broadcasting = A12a.broadcasting("points", "alice")
    namespace = Bus.prefix() || ""
    assert {:ok, 1} = PgStore.append(ScratchRepo, namespace, broadcasting, "\"old\"")
    socket = A12a.open!(port, A12a.cookie("alice"))
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert A12a.next_frame(socket) == %{"expect" => Frames.welcome()}
    subscribe(socket, id)
    assert A12a.next_frame(socket) == %{"expect" => Frames.confirm(id)}
    payload = ~s({ "place": "München", "values": [1, 2] })
    assert {:ok, 2} = PgStore.append(ScratchRepo, namespace, broadcasting, payload)
    poll()
    assert A12a.next_frame(socket) == %{"expect" => Frames.message(id, payload)}
    assert A12a.next_frame(socket, 100) == %{"error" => ":timeout"}
  end

  test "PG Bus loss disconnects existing sockets with server_restart and reconnect true",
       %{port: port} do
    id = ~s({"channel":"PointsChannel"})
    broadcasting = A12a.broadcasting("points", "alice")
    namespace = Bus.prefix() || ""
    socket = A12a.open!(port, A12a.cookie("alice"))
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert A12a.next_frame(socket) == %{"expect" => Frames.welcome()}
    subscribe(socket, id)
    assert A12a.next_frame(socket) == %{"expect" => Frames.confirm(id)}
    assert {:ok, 1} = PgStore.append(ScratchRepo, namespace, broadcasting, "\"unread\"")
    Process.exit(Process.whereis(Bus), :kill)
    assert A12a.next_frame(socket) == %{"expect" => Frames.disconnect("server_restart", true)}
    assert A12a.next_frame(socket) == %{"close" => 1000}
    stop_supervised!(Bus)
    [spec] = Bus.child_specs()
    start_supervised!(spec)
    fresh = A12a.open!(port, A12a.cookie("alice"))
    on_exit(fn -> :gen_tcp.close(fresh) end)
    assert A12a.next_frame(fresh) == %{"expect" => Frames.welcome()}
    subscribe(fresh, id)
    assert A12a.next_frame(fresh) == %{"expect" => Frames.confirm(id)}
    assert {:ok, 2} = PgStore.append(ScratchRepo, namespace, broadcasting, "\"fresh\"")
    poll()
    assert A12a.next_frame(fresh) == %{"expect" => Frames.message(id, "\"fresh\"")}
    assert A12a.next_frame(fresh, 100) == %{"error" => ":timeout"}
  end

  test "PG interleaved streams deliver only to their authenticated user", %{port: port} do
    id = ~s({"channel":"PointsChannel"})

    sockets =
      for who <- ["alice", "bob"] do
        socket = A12a.open!(port, A12a.cookie(who))
        on_exit(fn -> :gen_tcp.close(socket) end)
        assert A12a.next_frame(socket) == %{"expect" => Frames.welcome()}
        subscribe(socket, id)
        assert A12a.next_frame(socket) == %{"expect" => Frames.confirm(id)}
        {who, socket}
      end

    for seq <- 1..3, {who, _socket} <- Enum.reverse(sockets) do
      payload = Jason.encode!(%{owner: who, seq: seq})
      assert {:ok, _} = Bus.publish(A12a.broadcasting("points", who), payload)
    end

    poll()

    for {who, socket} <- sockets do
      for seq <- 1..3 do
        payload = Jason.encode!(%{owner: who, seq: seq})
        assert A12a.next_frame(socket) == %{"expect" => Frames.message(id, payload)}
      end

      assert A12a.next_frame(socket, 100) == %{"error" => ":timeout"}
    end
  end

  test "PG share-only identity rejects a user channel", %{port: port} do
    rejected_stream(port, "points_share_only", A12a.broadcasting("points", "alice"))
  end

  test "PG mismatched-share identity rejects another share stream", %{port: port} do
    id = A12a.case!("shared_mismatch") |> A12a.identifier() |> Jason.decode!()

    broadcasting =
      Dawarich.RailsMessages.broadcasting(["shared_location", {:shared_link, id["share_id"]}])

    rejected_stream(port, "shared_mismatch", broadcasting)
  end

  defp rejected_stream(port, name, broadcasting) do
    recorded = A12a.case!(name)
    socket = A12a.request!(port, recorded)
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert {101, _headers} = A12a.response_head(socket)
    assert A12a.next_frame(socket) == hd(recorded["steps"])
    id = A12a.identifier(recorded)
    subscribe(socket, id)
    assert A12a.next_frame(socket) == List.last(recorded["steps"])
    assert {:ok, _} = Bus.publish(broadcasting, "\"denied\"")
    poll()
    assert A12a.next_frame(socket, 100) == %{"error" => ":timeout"}
  end

  defp subscribe(socket, id),
    do: A12a.send_text(socket, Jason.encode!(%{command: "subscribe", identifier: id}))

  defp poll do
    send(Bus, :poll)
    :sys.get_state(Bus)
  end
end
