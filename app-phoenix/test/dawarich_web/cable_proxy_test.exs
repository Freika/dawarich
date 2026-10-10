defmodule DawarichWeb.CableProxyTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog

  alias Dawarich.Test.FakeCable
  alias DawarichWeb.{CableProxy, RailsProxy}

  @client_headers [
    {"Origin", "https://dawarich.example"},
    {"Cookie", "other_app=Gr\xC3\xBC\xC3\x9Fe; _dawarich_session=abc"},
    {"Sec-WebSocket-Protocol", "actioncable-v1-json, actioncable-unsupported"},
    {"Sec-WebSocket-Extensions", "permessage-deflate"},
    {"X-Forwarded-For", "203.0.113.9"},
    {"X-Dawarich-Remote-Addr", "6.6.6.6"}
  ]

  @key "Sec-WebSocket-Key: #{Base.encode64("the sample nonce")}\r\n"

  defp serve(upstream_port) do
    bandit =
      start_supervised!(
        {Bandit,
         [plug: {RailsProxy, upstream: {{127, 0, 0, 1}, upstream_port}}] ++
           Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    {bandit, port}
  end

  defp proxy(upstream_port), do: upstream_port |> serve() |> elem(1)

  test "the upgrade reaches Puma with the client's headers, and Puma's subprotocol reaches the client" do
    port = proxy(FakeCable.start(self()))
    socket = ws_request(port, "/cable?share_id=7", @client_headers)

    assert {101, headers, _rest} = read_response_head(socket)
    assert values(headers, "sec-websocket-protocol") == ["actioncable-v1-json"]
    assert values(headers, "cache-control") == []

    event =
      receive do
        {:cable_request, _, _, _} = event -> event
      end

    assert {:cable_request, "/cable", "share_id=7", upstream} = event

    assert {"origin", "https://dawarich.example"} in upstream
    assert {"cookie", "other_app=Gr\xC3\xBC\xC3\x9Fe; _dawarich_session=abc"} in upstream
    assert {"sec-websocket-key", Base.encode64("the sample nonce")} in upstream

    assert for(
             {name, _} <- upstream,
             name in ["user-agent", "sec-websocket-extensions"],
             do: name
           ) == []

    assert {"sec-websocket-protocol", "actioncable-v1-json, actioncable-unsupported"} in upstream
    assert {"x-forwarded-for", "203.0.113.9"} in upstream
    assert {"host", "127.0.0.1:#{port}"} in upstream
    assert for({"x-dawarich-remote-addr", value} <- upstream, do: value) == ["127.0.0.1"]
    assert for({"connection", value} <- upstream, do: value) == ["Upgrade"]
  end

  test "a client cannot erase the forwarding headers of an upgrade by naming them in Connection" do
    upstream = listen()
    port = proxy(upstream.port)
    client = connect(port)

    {puma, :ok} =
      accept_on_request(upstream, fn ->
        send_raw(client, [
          "GET /cable HTTP/1.1\r\nHost: a\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\n",
          @key,
          "Connection: Upgrade, X-Forwarded-For, X-Forwarded-Proto, Forwarded, Host\r\n",
          "X-Forwarded-For: 203.0.113.9\r\nX-Forwarded-Proto: https\r\nForwarded: for=198.51.100.1\r\n\r\n"
        ])
      end)

    {head, _} = read_head(puma)

    assert header(head, "host") == ["a"]
    assert header(head, "x-forwarded-for") == ["203.0.113.9"]
    assert header(head, "x-forwarded-proto") == ["https"]
    assert header(head, "forwarded") == ["for=198.51.100.1"]
    assert header(head, "connection") == ["Upgrade"]
    reply(puma, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
    assert {404, _, ""} = read_response(client)
  end

  for {form, version, headers} <- [
        {"without a key", "HTTP/1.1", "Sec-WebSocket-Version: 13\r\n"},
        {"of version 8", "HTTP/1.1", "Sec-WebSocket-Version: 8\r\n" <> @key},
        {"over HTTP/1.0", "HTTP/1.0", "Sec-WebSocket-Version: 13\r\n" <> @key}
      ] do
    test "an upgrade #{form} gets 400 and never reaches Puma" do
      upstream = listen()
      {bandit, port} = serve(upstream.port)
      client = connect(port)

      {pids, log} =
        with_log([level: :error, metadata: [:pid]], fn ->
          send_raw(client, [
            "GET /cable #{unquote(version)}\r\nHost: a\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n",
            unquote(headers),
            "\r\n"
          ])

          assert {400, _headers, _rest} = read_response_head(client)
          {:ok, pids} = ThousandIsland.connection_pids(bandit)
          refs = Enum.map(pids, &Process.monitor/1)
          :ok = :gen_tcp.close(client)

          for ref <- refs do
            event =
              receive do
                {:DOWN, ^ref, :process, _, _} = event -> event
              end

            assert {:DOWN, ^ref, :process, _, reason} = event

            assert reason in [:normal, :noproc] or match?({:shutdown, _}, reason),
                   "connection process for #{unquote(form)} exited with #{inspect(reason)} instead of a normal shutdown"
          end

          pids
        end)

      assert :gen_tcp.accept(upstream.listen, 100) == {:error, :timeout}

      for pid <- pids do
        own_log = log_for_pid(log, pid)
        refute own_log =~ "UpgradeError"
        refute own_log =~ "DawarichWeb"
      end
    end
  end

  test "frames flow both ways and Puma's close code reaches the client" do
    port = proxy(FakeCable.start(self()))
    socket = ws_request(port, "/cable", @client_headers)
    {101, _headers, rest} = read_response_head(socket)

    assert {{:text, ~s({"type":"welcome"})}, rest} = ws_recv(socket, rest)
    ws_send_text(socket, "subscribe")
    assert {{:text, "SUBSCRIBE"}, rest} = ws_recv(socket, rest)
    ws_send_text(socket, "bye")
    assert {{:close, <<4000::16, "bye">>}, _rest} = ws_recv(socket, rest)
  end

  test "a frame Puma writes together with its 101 reaches the client" do
    upstream = listen()
    port = proxy(upstream.port)

    {puma, socket} =
      accept_on_request(upstream, fn -> ws_request(port, "/cable", @client_headers) end)

    {head, _} = read_head(puma)
    key = head |> header("sec-websocket-key") |> hd()
    accept_key = Base.encode64(:crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))

    reply(puma, [
      "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n",
      "Sec-WebSocket-Accept: #{accept_key}\r\nSec-WebSocket-Protocol: actioncable-v1-json\r\n\r\n",
      server_text_frame(~s({"type":"welcome"}))
    ])

    {101, _headers, rest} = read_response_head(socket)
    assert {{:text, ~s({"type":"welcome"})}, _} = ws_recv(socket, rest)
  end

  test "a refused upgrade comes back as Puma's HTTP response" do
    port = proxy(FakeCable.start(self()))
    socket = ws_request(port, "/cable", [{"X-Refuse", "1"} | @client_headers])

    assert {404, headers, rest} = read_response_head(socket)
    assert values(headers, "sec-websocket-accept") == []
    assert read_at_least(socket, rest, 14) == "Page not found"
  end

  test "a client that goes away closes Puma's side" do
    port = proxy(FakeCable.start(self()))
    socket = ws_request(port, "/cable", @client_headers)
    {101, _headers, _rest} = read_response_head(socket)

    ws_close(socket, 1000)

    event =
      receive do
        {:cable_closed, _} = event -> event
      end

    assert {:cable_closed, :remote} = event
  end

  test "a client that drops the connection closes Puma's side" do
    port = proxy(FakeCable.start(self()))
    socket = ws_request(port, "/cable", @client_headers)
    {101, _headers, _rest} = read_response_head(socket)

    :ok = :gen_tcp.close(socket)

    event =
      receive do
        {:cable_closed, _} = event -> event
      end

    assert {:cable_closed, :remote} = event
  end

  test "Puma going away closes the client with 1011" do
    {socket, puma, rest, connection} = upgraded(listen())
    ref = make_ref()
    owner = self()

    :ok =
      :telemetry.attach(
        ref,
        [:bandit, :websocket, :stop],
        fn _, _, _, _ ->
          if self() == connection, do: send(owner, {ref, :close_sent})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(ref) end)

    :ok = :gen_tcp.close(puma)

    event =
      receive do
        {^ref, _} = event -> event
      end

    assert {^ref, :close_sent} = event

    assert {{:close, <<1011::16>>}, _rest} = ws_recv(socket, rest)
  end

  test "an unreachable Puma answers the upgrade with 502" do
    upstream = listen()
    :ok = :gen_tcp.close(upstream.listen)
    port = proxy(upstream.port)

    assert {502, _headers, _rest} =
             port |> ws_request("/cable", @client_headers) |> read_response_head()
  end

  test "fragmented messages and pings from Puma are relayed, and a close without a code becomes 1000" do
    {socket, puma, rest, _connection} = upgraded(listen())

    reply(puma, [
      server_frame(1, "wel", 0),
      server_frame(9, "p"),
      server_frame(0, "come"),
      server_frame(8, "")
    ])

    assert {{:text, "welcome"}, rest} = ws_recv(socket, rest)
    assert {{:close, <<1000::16>>}, _rest} = ws_recv(socket, rest)
    assert {10, "p", _} = masked_recv(puma, "")
  end

  test "a frame Puma should never send closes the client with 1002" do
    {socket, puma, rest, _connection} = upgraded(listen())

    reply(puma, <<1::1, 0::3, 1::4, 1::1, 1::7, 0::32, "x">>)

    assert {{:close, <<1002::16>>}, _rest} = ws_recv(socket, rest)
  end

  test "cable connections are never closed for silence" do
    assert CableProxy.upgrade_options()[:timeout] == :infinity
  end

  defp upgraded(upstream) do
    {bandit, port} = serve(upstream.port)

    {puma, socket} =
      accept_on_request(upstream, fn -> ws_request(port, "/cable", @client_headers) end)

    {head, _} = read_head(puma)
    key = head |> header("sec-websocket-key") |> hd()
    accept_key = Base.encode64(:crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))

    reply(
      puma,
      "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept_key}\r\n\r\n"
    )

    {101, _headers, rest} = read_response_head(socket)
    {:ok, [connection]} = ThousandIsland.connection_pids(bandit)
    {socket, puma, rest, connection}
  end

  defp masked_recv(socket, acc) do
    case acc do
      <<_::4, opcode::4, 1::1, size::7, mask::binary-size(4), payload::binary-size(size),
        rest::binary>>
      when size < 126 ->
        {opcode,
         :crypto.exor(payload, binary_part(:binary.copy(mask, div(size, 4) + 1), 0, size)), rest}

      _ ->
        {:ok, data} = :gen_tcp.recv(socket, 0, :infinity)
        masked_recv(socket, acc <> data)
    end
  end
end
