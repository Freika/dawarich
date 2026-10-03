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

  test "a Bus DOWN for the monitored Bus stops the socket; other DOWNs are ignored" do
    state = A12a.socket_state(%{user: A12a.user!("alice"), share: nil})
    {:ok, state} = Socket.handle_in({A12a.subscribe_frame("PointsChannel"), opcode: :text}, state)
    assert is_reference(state.bus)
    down = {:DOWN, state.bus, :process, Dawarich.Cable.Bus, :killed}

    assert {:stop, :normal, 1000, [{:text, frame}], _} = Socket.handle_info(down, state)
    assert frame == Frames.disconnect("server_restart", true)
    assert {:ok, _} = Socket.handle_info({:DOWN, make_ref(), :process, self(), :normal}, state)
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

  test "a malformed upgrade gets Phoenix's 400 (ED-057)", %{port: port} do
    assert A12a.replay(port, A12a.case!("version_8")) ==
             {400, nil, "text/plain; charset=utf-8", "Bad Request", []}
  end

  test "a socket whose Bus goes down is told to reconnect, as Rails' server restart does",
       %{port: port} do
    socket = A12a.open!(port, A12a.cookie("alice"))
    assert A12a.ws_recv_json(socket) == %{"type" => "welcome"}
    A12a.send_text(socket, A12a.subscribe_frame("PointsChannel"))
    assert %{"expect" => confirm} = A12a.next_frame(socket)
    assert confirm == Frames.confirm(~s({"channel":"PointsChannel"}))

    Process.exit(Process.whereis(Dawarich.Cable.Bus), :kill)
    assert A12a.next_frame(socket) == %{"expect" => Frames.disconnect("server_restart", true)}
    assert A12a.next_frame(socket) == %{"close" => 1000}
  end

  test "a silent socket is closed after its bounded lifetime (ED-329)" do
    port = A12a.serve_cable!(silent_ms: 100)
    socket = A12a.open!(port, A12a.cookie("dave_locked"))
    assert {_fin, :close, <<1000::16, _::binary>>} = A12a.ws_recv_any(socket, 2_000)
  end

  test "a failing identity lookup leaves the socket silent, as Rails' failing connect does",
       %{port: port} do
    :ok = Ecto.Adapters.SQL.Sandbox.checkin(Dawarich.Repo)
    socket = A12a.open!(port, A12a.cookie("alice"))
    assert A12a.ws_recv_any(socket, 300) == :timeout
  end

  test "each Phoenix-held upgrade is logged once", %{port: port} do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        socket = A12a.open!(port, A12a.cookie("alice"))
        assert A12a.ws_recv_json(socket) == %{"type" => "welcome"}
      end)

    assert log =~ "[Cable] Phoenix upgraded /cable"
  end
end
