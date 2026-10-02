defmodule DawarichWeb.CableTest do
  use Dawarich.IngestCase, async: false

  import Dawarich.Test.RawHTTP, only: [ws_request: 4, read_response: 1, values: 2]

  alias Dawarich.Cable.Frames
  alias Dawarich.Test.A12a
  alias DawarichWeb.Cable.Socket

  setup do
    A12a.seed!()
    A12a.start_bus!()
    {:ok, port: A12a.serve_cable!(beat_ms: 50, env: %{})}
  end

  test "a plain GET and a foreign origin answer Rails' 404 page", %{port: port} do
    for headers <- [[{"Origin", "http://other.example"}], []] do
      socket = ws_request(port, "/cable", headers, "www.example.com")
      assert {404, head, body} = read_response(socket)
      assert values(head, "content-type") == ["text/plain; charset=utf-8"]
      assert body == "Page not found"
    end
  end

  test "the origin check uses Rack's scheme and the raw Host; development also allows localhost" do
    https = A12a.conn_with(origin: "https://www.example.com", forwarded_proto: "https")
    assert DawarichWeb.Cable.origin?(https, %{})
    localhost = A12a.conn_with(origin: "http://localhost:3000")
    refute DawarichWeb.Cable.origin?(localhost, %{"RAILS_ENV" => "production"})
    assert DawarichWeb.Cable.origin?(localhost, %{"RAILS_ENV" => "development"})
  end

  test "the subprotocol is the client's first offer Rails supports" do
    assert DawarichWeb.Cable.protocol(["actioncable-unsupported", "actioncable-v1-json"]) ==
             "actioncable-unsupported"

    assert DawarichWeb.Cable.protocol(["x", "actioncable-v1-json"]) == "actioncable-v1-json"
    assert DawarichWeb.Cable.protocol(["x"]) == nil
  end

  test "pings follow the welcome every beat with integer seconds", %{port: port} do
    socket = A12a.open!(port, A12a.cookie("alice"))
    assert A12a.ws_recv_json(socket) == %{"type" => "welcome"}
    assert %{"type" => "ping", "message" => s1} = A12a.ws_recv_json(socket)
    assert %{"type" => "ping", "message" => s2} = A12a.ws_recv_json(socket)
    assert is_integer(s1) and s2 >= s1
  end

  test "a streaming subscription is confirmed only when Redis acknowledges it" do
    state = A12a.socket_state(%{user: A12a.user!("alice"), share: nil})
    {:ok, state} = Socket.handle_in({A12a.subscribe_frame("PointsChannel"), opcode: :text}, state)
    {:ok, state} = Socket.handle_in({A12a.subscribe_frame("PointsChannel"), opcode: :text}, state)
    b = A12a.broadcasting("points", "alice")
    assert {:push, [{:text, confirm}], state} = Socket.handle_info(A12a.subscribed(b), state)
    assert confirm == Frames.confirm(~s({"channel":"PointsChannel"}))
    assert {:ok, _} = Socket.handle_info(A12a.subscribed(b), state)

    assert {:push, [{:text, frame}], _} =
             Socket.handle_info(A12a.redis_message(b, ~s([1])), state)

    assert frame == Frames.message(~s({"channel":"PointsChannel"}), ~s([1]))
  end

  test "unsubscribe stops delivery; unknown identifiers and commands send nothing" do
    state = A12a.confirmed_state("PointsChannel", "alice")
    unsubscribe = {A12a.unsubscribe_frame("PointsChannel"), opcode: :text}
    {:ok, state} = Socket.handle_in(unsubscribe, state)
    message = A12a.redis_message(A12a.broadcasting("points", "alice"), "1")
    assert {:ok, _} = Socket.handle_info(message, state)

    for text <- [A12a.unsubscribe_frame("TracksChannel"), ~s({"command":"nope"}), "{", "[1]"],
        do: assert({:ok, _} = Socket.handle_in({text, opcode: :text}, state))

    assert {:ok, _} = Socket.handle_in({<<1, 2>>, opcode: :binary}, state)
  end

  test "unauthorized gets the disconnect frame then close 1000; silent gets nothing and stays open",
       %{port: port} do
    assert {:stop, :normal, 1000, [{:text, frame}], _} =
             Socket.init(A12a.init_state(:unauthorized))

    assert frame == Frames.disconnect("unauthorized", false)
    assert {:ok, state} = Socket.init(A12a.init_state(:silent))
    subscribe = {A12a.subscribe_frame("PointsChannel"), opcode: :text}
    assert {:ok, ^state} = Socket.handle_in(subscribe, state)

    socket = A12a.open!(port, A12a.cookie("dave_locked"))
    assert A12a.ws_recv_any(socket, 300) == :timeout
    assert :inet.peername(socket) |> elem(0) == :ok
  end
end
