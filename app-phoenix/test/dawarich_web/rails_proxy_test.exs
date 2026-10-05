defmodule DawarichWeb.RailsProxyTest do
  use ExUnit.Case, async: true

  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog

  alias DawarichWeb.RailsProxy

  setup do
    upstream = listen()

    bandit =
      start_supervised!(
        {Bandit,
         [plug: {RailsProxy, upstream: {{127, 0, 0, 1}, upstream.port}}] ++
           Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    %{upstream: upstream, port: port, bandit: bandit}
  end

  test "Puma receives the request as the client sent it, plus Phoenix's client address", ctx do
    client = connect(ctx.port)

    send_raw(client, [
      "POST /imports?kind=gpx&x=%E2%9C%93 HTTP/1.1\r\nHost: dawarich.example:3000\r\n",
      "X-Forwarded-For: 203.0.113.9\r\nX-Forwarded-Proto: https\r\nForwarded: for=198.51.100.1\r\n",
      "Client-IP: 192.0.2.4\r\nCookie: _dawarich_session=abc%2Bdef\r\n",
      "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 11\r\n\r\na=1&b=%20ok"
    ])

    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)

    assert request_line(head) == "POST /imports?kind=gpx&x=%E2%9C%93 HTTP/1.1"
    assert header(head, "host") == ["dawarich.example:3000"]
    assert header(head, "x-forwarded-for") == ["203.0.113.9"]
    assert header(head, "x-forwarded-proto") == ["https"]
    assert header(head, "forwarded") == ["for=198.51.100.1"]
    assert header(head, "client-ip") == ["192.0.2.4"]
    assert header(head, "cookie") == ["_dawarich_session=abc%2Bdef"]
    assert header(head, "content-length") == ["11"]
    assert header(head, "x-dawarich-remote-addr") == ["127.0.0.1"]
    assert read_at_least(puma, rest, 11) == "a=1&b=%20ok"

    reply(puma, "HTTP/1.1 204 No Content\r\n\r\n")
    assert {204, _headers, ""} = read_response(client)
  end

  test "the request target reaches Puma byte for byte", ctx do
    client = connect(ctx.port)

    send_raw(
      client,
      "GET /api/v1/points//x%2Fy?start_at=2024-01-01T00%3A00%3A00Z&q=a+b HTTP/1.1\r\nHost: a\r\n\r\n"
    )

    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    assert request_line(head) ==
             "GET /api/v1/points//x%2Fy?start_at=2024-01-01T00%3A00%3A00Z&q=a+b HTTP/1.1"

    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    assert {200, _, ""} = read_response(client)
  end

  test "a client cannot choose the address Puma records", ctx do
    client = connect(ctx.port)

    send_raw(
      client,
      "GET / HTTP/1.1\r\nHost: a\r\nX-Dawarich-Remote-Addr: 6.6.6.6\r\nx-dawarich-remote-addr: 7.7.7.7\r\n\r\n"
    )

    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    assert header(head, "x-dawarich-remote-addr") == ["127.0.0.1"]
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    assert {200, _, ""} = read_response(client)
  end

  test "a client cannot strip the body's length and smuggle a second request to Puma", ctx do
    client = connect(ctx.port)
    smuggled = "GET /admin HTTP/1.1\r\nHost: a\r\nX-Dawarich-Remote-Addr: 6.6.6.6\r\n\r\n"

    send_raw(client, [
      "POST / HTTP/1.1\r\nHost: a\r\nConnection: content-length\r\n",
      "Content-Length: #{byte_size(smuggled)}\r\n\r\n",
      smuggled
    ])

    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)

    assert header(head, "content-length") == ["#{byte_size(smuggled)}"]
    assert header(head, "connection") == ["close"]
    assert read_at_least(puma, rest, byte_size(smuggled)) == smuggled
    reply(puma, "HTTP/1.1 204 No Content\r\n\r\n")
    assert {204, _, ""} = read_response(client)
  end

  test "a client cannot strip the chunked framing of its body", ctx do
    client = connect(ctx.port)

    send_raw(client, [
      "POST / HTTP/1.1\r\nHost: a\r\nConnection: transfer-encoding\r\n",
      "Transfer-Encoding: chunked\r\n\r\n4\r\nabcd\r\n0\r\n\r\n"
    ])

    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)

    assert header(head, "transfer-encoding") == ["chunked"]
    assert header(head, "content-length") == []
    assert dechunk(puma, rest) == "abcd"
    reply(puma, "HTTP/1.1 204 No Content\r\n\r\n")
    assert {204, _, ""} = read_response(client)
  end

  test "a client cannot nominate the recorded address away", ctx do
    client = connect(ctx.port)

    send_raw(client, [
      "GET / HTTP/1.1\r\nHost: a\r\nConnection: x-dawarich-remote-addr\r\n",
      "X-Dawarich-Remote-Addr: 6.6.6.6\r\n\r\n"
    ])

    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    assert header(head, "x-dawarich-remote-addr") == ["127.0.0.1"]
    reply(puma, "HTTP/1.1 204 No Content\r\n\r\n")
    assert {204, _, ""} = read_response(client)
  end

  test "hop-by-hop request headers stop at Phoenix, and a header the client names in Connection goes on",
       ctx do
    client = connect(ctx.port)

    send_raw(client, [
      "GET / HTTP/1.1\r\nHost: a\r\nConnection: keep-alive, X-Hop\r\nX-Hop: 1\r\nKeep-Alive: timeout=5\r\n",
      "TE: trailers\r\nProxy-Connection: keep-alive\r\nX-End-To-End: kept\r\n\r\n"
    ])

    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    for name <- ~w(keep-alive te proxy-connection upgrade transfer-encoding expect),
        do: assert(header(head, name) == [], "#{name} was forwarded")

    assert header(head, "x-hop") == ["1"]
    assert header(head, "x-end-to-end") == ["kept"]
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    assert {200, _, ""} = read_response(client)
  end

  test "a client cannot erase the forwarding headers by naming them in Connection", ctx do
    client = connect(ctx.port)

    send_raw(client, [
      "GET / HTTP/1.1\r\nHost: a\r\nConnection: X-Forwarded-For, X-Forwarded-Proto, Forwarded, Host\r\n",
      "X-Forwarded-For: 203.0.113.9\r\nX-Forwarded-Proto: https\r\nForwarded: for=198.51.100.1\r\n\r\n"
    ])

    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    assert header(head, "host") == ["a"]
    assert header(head, "x-forwarded-for") == ["203.0.113.9"]
    assert header(head, "x-forwarded-proto") == ["https"]
    assert header(head, "forwarded") == ["for=198.51.100.1"]
    assert header(head, "connection") == ["close"]
    reply(puma, "HTTP/1.1 204 No Content\r\n\r\n")
    assert {204, _, ""} = read_response(client)
  end

  test "response headers reach the client as Puma sent them, repeated Set-Cookie included", ctx do
    client = connect(ctx.port)
    send_raw(client, "GET /users/sign_in HTTP/1.1\r\nHost: a\r\n\r\n")
    puma = accept(ctx.upstream)
    _ = read_head(puma)

    reply(puma, [
      "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nSet-Cookie: a=1; path=/\r\n",
      "Set-Cookie: b=2; path=/; httponly\r\nX-Request-Id: r1\r\nKeep-Alive: timeout=9\r\n",
      "Connection: X-Private\r\nX-Private: 1\r\nContent-Length: 2\r\n\r\nok"
    ])

    assert {200, headers, "ok"} = read_response(client)
    assert values(headers, "set-cookie") == ["a=1; path=/", "b=2; path=/; httponly"]
    assert values(headers, "content-type") == ["text/html; charset=utf-8"]
    assert values(headers, "x-request-id") == ["r1"]
    assert values(headers, "content-length") == ["2"]
    assert values(headers, "cache-control") == []
    assert values(headers, "keep-alive") == []
    assert values(headers, "x-private") == []
  end

  test "response header matching is ASCII case-insensitive without changing a non-ASCII value" do
    headers =
      DawarichWeb.RailsProxy.Headers.response([
        {"cOnNeCtIoN", "X-pRiVaTe"},
        {"X-pRiVaTe", "1"},
        {"X-Device-Name", "München"}
      ])

    refute {"x-private", "1"} in headers
    assert {"x-device-name", "München"} in headers
  end

  test "a long response streams to the client with its length and without buffering", ctx do
    client = connect(ctx.port)

    {puma, :ok} =
      accept_on_request(ctx.upstream, fn ->
        send_raw(client, "GET /big.bin HTTP/1.1\r\nHost: a\r\n\r\n")
      end)

    _ = read_head(puma)
    mib = :binary.copy("x", 1_048_576)

    reply(puma, ["HTTP/1.1 200 OK\r\nContent-Length: 3145728\r\n\r\n", mib])
    {200, headers, rest} = read_response_head(client)

    assert values(headers, "content-length") == ["3145728"]
    assert values(headers, "transfer-encoding") == []
    first = read_at_least(client, rest, 1_048_576)

    reply(puma, [mib, mib])
    assert read_at_least(client, first, 3_145_728) == :binary.copy("x", 3_145_728)
  end

  test "a chunked response stays chunked", ctx do
    client = connect(ctx.port)
    send_raw(client, "GET /export HTTP/1.1\r\nHost: a\r\nAccept-Encoding: deflate\r\n\r\n")
    puma = accept(ctx.upstream)
    _ = read_head(puma)

    reply(
      puma,
      "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
    )

    assert {200, headers, "hello world"} = read_response(client)
    assert values(headers, "transfer-encoding") == ["chunked"]
    assert values(headers, "content-encoding") == []
  end

  test "a long response is read from Puma in large pieces, not 1460-byte ones", ctx do
    client = connect(ctx.port)
    send_raw(client, "GET /export HTTP/1.1\r\nHost: a\r\n\r\n")
    puma = accept(ctx.upstream)
    _ = read_head(puma)
    mib = :binary.copy("z", 1_048_576)

    sender =
      Task.async(fn ->
        reply(puma, [
          "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n100000\r\n",
          mib,
          "\r\n0\r\n\r\n"
        ])
      end)

    {200, _headers, rest} = read_response_head(client)
    pieces = chunks(client, rest)
    Task.await(sender, :infinity)

    assert IO.iodata_to_binary(pieces) == mib
    assert length(pieces) <= 128
  end

  test "a large upload reaches Puma while the client is still sending", ctx do
    client = connect(ctx.port)
    mib = :binary.copy("y", 1_048_576)

    send_raw(client, [
      "PUT /rails/active_storage/disk/token/a.zip HTTP/1.1\r\nHost: a\r\nContent-Length: 8388608\r\n\r\n",
      mib,
      mib
    ])

    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)
    assert header(head, "content-length") == ["8388608"]
    early = read_at_least(puma, rest, 1_048_576)

    send_raw(client, :binary.copy(mib, 6))
    assert read_at_least(puma, early, 8_388_608) == :binary.copy("y", 8_388_608)

    reply(puma, "HTTP/1.1 204 No Content\r\n\r\n")
    assert {204, _, ""} = read_response(client)
  end

  test "a chunked upload is forwarded chunked", ctx do
    client = connect(ctx.port)

    send_raw(
      client,
      "POST /api/v1/points HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nabcd\r\n3\r\nefg\r\n0\r\n\r\n"
    )

    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)

    assert header(head, "transfer-encoding") == ["chunked"]
    assert header(head, "content-length") == []
    assert dechunk(puma, rest) == "abcdefg"
    reply(puma, "HTTP/1.1 201 Created\r\nContent-Length: 0\r\n\r\n")
    assert {201, _, ""} = read_response(client)
  end

  test "HEAD and 304 keep Puma's headers, send no body and leave the connection usable", ctx do
    client = connect(ctx.port)
    send_raw(client, "HEAD /big.bin HTTP/1.1\r\nHost: a\r\n\r\n")
    puma = accept(ctx.upstream)
    _ = read_head(puma)

    reply(
      puma,
      "HTTP/1.1 200 OK\r\nContent-Length: 1234\r\nContent-Type: application/octet-stream\r\n\r\n"
    )

    assert {200, headers, ""} = read_response(client, method: "HEAD")
    assert values(headers, "content-length") == ["1234"]

    send_raw(client, "GET /cached HTTP/1.1\r\nHost: a\r\nIf-None-Match: \"v1\"\r\n\r\n")
    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)
    assert request_line(head) == "GET /cached HTTP/1.1"
    reply(puma, "HTTP/1.1 304 Not Modified\r\nETag: \"v1\"\r\n\r\n")

    assert {304, headers, ""} = read_response(client)
    assert values(headers, "etag") == ["\"v1\""]
  end

  test "Expect: 100-continue is answered by Phoenix and not forwarded", ctx do
    client = connect(ctx.port)

    send_raw(
      client,
      "POST /x HTTP/1.1\r\nHost: a\r\nExpect: 100-continue\r\nContent-Length: 3\r\n\r\n"
    )

    assert {100, _, _} = read_response_head(client)

    send_raw(client, "abc")
    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)
    assert header(head, "expect") == []
    assert read_at_least(puma, rest, 3) == "abc"
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    assert {200, _, ""} = read_response(client)
  end

  test "a 70 KiB cookie header passes, as it does on Puma", ctx do
    client = connect(ctx.port)
    cookie = "a=" <> :binary.copy("b", 70_000)
    send_raw(client, "GET / HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n\r\n")
    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    assert header(head, "cookie") == [cookie]
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    assert {200, _, ""} = read_response(client)
  end

  test "an upstream that dies mid-body closes the client connection before the body is complete",
       ctx do
    client = connect(ctx.port)

    log =
      capture_log(fn ->
        send_raw(client, "GET /export.zip HTTP/1.1\r\nHost: a\r\n\r\n")
        puma = accept(ctx.upstream)
        _ = read_head(puma)
        reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n0123456789")
        :ok = :gen_tcp.close(puma)

        assert {:closed, received} = read_until_closed(client)
        assert received =~ "content-length: 100"
        assert String.ends_with?(received, "0123456789")
      end)

    assert log =~ "Puma closed the proxied response early"
  end

  test "a client that aborts a download closes Puma's connection and logs nothing", ctx do
    client = connect(ctx.port)

    {handler, log} =
      with_log([metadata: [:pid]], fn ->
        send_raw(client, "GET /export.zip HTTP/1.1\r\nHost: a\r\n\r\n")
        puma = accept(ctx.upstream)
        _ = read_head(puma)

        reply(puma, [
          "HTTP/1.1 200 OK\r\nContent-Length: 1000000000\r\n\r\n",
          :binary.copy("x", 65_536)
        ])

        {200, _headers, _rest} = read_response_head(client)
        {:ok, [handler]} = ThousandIsland.connection_pids(ctx.bandit)
        monitor = Process.monitor(handler)
        :ok = :gen_tcp.close(client)

        assert {:error, reason} =
                 send_until_closed(puma, :binary.copy("y", 65_536), 64 * 1_048_576)

        assert reason in [:closed, :econnreset]

        event =
          receive do
            {:DOWN, ^monitor, :process, _, _} = event -> event
          end

        assert {:DOWN, ^monitor, :process, _, down_reason} = event

        assert down_reason == :normal or match?({:shutdown, _}, down_reason),
               "connection process exited with #{inspect(down_reason)} instead of a normal shutdown"

        handler
      end)

    refute log_for_pid(log, handler) =~ ~r/Puma closed|Puma did not answer|Bandit/
  end

  test "requests Puma accepts reach it unchanged, with only Phoenix's headers added", ctx do
    cases = [
      {"GET /search?q=a|b{}^`\\&t=\xC3\xBC HTTP/1.1",
       [
         "Host: a",
         "Cookie: other_app=Gr\xC3\xBC\xC3\x9Fe; _dawarich_session=abc",
         "X-Device-Name: Pixel \xE2\x80\x98K\xC3\xBCche\xE2\x80\x99"
       ]},
      {"GET /search?q=100% HTTP/1.1", ["Host: a"]},
      {"GET /api/v1/health HTTP/1.1", ["Host: a", "Accept: */*"]},
      {"GET / HTTP/1.0", []}
    ]

    for {line, headers} <- cases do
      client = connect(ctx.port)
      send_raw(client, [line, "\r\n", Enum.map(headers, &[&1, "\r\n"]), "\r\n"])
      puma = accept(ctx.upstream)
      {head, _} = read_head(puma)

      assert String.split(head, "\r\n") ==
               [String.replace_suffix(line, "HTTP/1.0", "HTTP/1.1")] ++
                 Enum.map(headers, &downcase_name/1) ++
                 ["connection: close", "x-dawarich-remote-addr: 127.0.0.1"]

      reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
      assert {200, _, ""} = read_response(client)
    end
  end

  test "an IPv4 client of a dual-stack listener is recorded by its IPv4 address, an IPv6 client by its own",
       ctx do
    bandit =
      start_supervised!(
        {Bandit,
         [plug: {RailsProxy, upstream: {{127, 0, 0, 1}, ctx.upstream.port}}] ++
           Dawarich.Front.http_options({0, 0, 0, 0, 0, 0, 0, 0}, 0)},
        id: :dual_stack
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    for {address, expected} <- [{{127, 0, 0, 1}, "127.0.0.1"}, {{0, 0, 0, 0, 0, 0, 0, 1}, "::1"}] do
      {:ok, client} = :gen_tcp.connect(address, port, [:binary, active: false])
      send_raw(client, "GET / HTTP/1.1\r\nHost: a\r\n\r\n")
      puma = accept(ctx.upstream)
      {head, _} = read_head(puma)

      assert header(head, "x-dawarich-remote-addr") == [expected]
      reply(puma, "HTTP/1.1 204 No Content\r\n\r\n")
      assert {204, _, ""} = read_response(client)
    end
  end

  test "a slow upload may pause as long as Puma allows" do
    assert Keyword.fetch!(RailsProxy.read_options(), :read_timeout) == 60_000
  end

  defp downcase_name(header) do
    [name, value] = String.split(header, ": ", parts: 2)
    String.downcase(name) <> ": " <> value
  end

  defp send_until_closed(_socket, _data, budget) when budget <= 0, do: :still_open

  defp send_until_closed(socket, data, budget) do
    case :gen_tcp.send(socket, data) do
      :ok -> send_until_closed(socket, data, budget - byte_size(data))
      error -> error
    end
  end

  test "when Puma does not answer, the client gets 502 and nothing about the upstream", ctx do
    :ok = :gen_tcp.close(ctx.upstream.listen)
    client = connect(ctx.port)

    log =
      capture_log(fn ->
        send_raw(client, "GET / HTTP/1.1\r\nHost: a\r\n\r\n")
        assert {502, headers, "Bad Gateway"} = read_response(client)
        assert values(headers, "content-type") == ["text/plain; charset=utf-8"]
      end)

    assert log =~ "Puma did not answer the proxied request"
  end
end
