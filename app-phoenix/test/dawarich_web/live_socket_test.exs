defmodule DawarichWeb.LiveSocketTest do
  use ExUnit.Case, async: false

  import Dawarich.Test.RawHTTP

  alias DawarichWeb.Origin

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {"127.0.0.1", upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    %{upstream: upstream, port: port}
  end

  test "an Origin is allowed when its host is one of APPLICATION_HOSTS, whatever its scheme or port" do
    hosts = "dawarich.example, .family.example"

    assert Origin.allowed?(URI.parse("https://dawarich.example"), hosts)
    assert Origin.allowed?(URI.parse("http://dawarich.example:3000"), hosts)
    assert Origin.allowed?(URI.parse("https://family.example"), hosts)
    assert Origin.allowed?(URI.parse("https://maps.family.example"), hosts)
    refute Origin.allowed?(URI.parse("https://evil.example"), hosts)
    refute Origin.allowed?(URI.parse("https://dawarich.example.evil.example"), hosts)
    refute Origin.allowed?(URI.parse("https://evilfamily.example"), hosts)
    assert Origin.allowed?(URI.parse("http://localhost:3000"), nil)
    refute Origin.allowed?(URI.parse("http://127.0.0.1:3000"), nil)
  end

  test "behind a TLS-terminating proxy the socket accepts its own https Origin and refuses a foreign one",
       ctx do
    System.put_env("APPLICATION_HOSTS", "dawarich.example")
    on_exit(fn -> System.delete_env("APPLICATION_HOSTS") end)
    path = "/phoenix/live/websocket?vsn=2.0.0"

    own =
      ws_request(
        ctx.port,
        path,
        [{"Origin", "https://dawarich.example"}, {"X-Forwarded-Proto", "https"}],
        "dawarich.example"
      )

    assert {101, _headers, _rest} = read_response_head(own)

    foreign =
      ws_request(
        ctx.port,
        path,
        [{"Origin", "https://evil.example"}, {"X-Forwarded-Proto", "https"}],
        "dawarich.example"
      )

    assert {403, _headers, _rest} = read_response_head(foreign)
  end

  test "Phoenix's own socket path is never proxied", ctx do
    client = connect(ctx.port)
    send_raw(client, "GET /phoenix/live/websocket HTTP/1.1\r\nHost: a\r\n\r\n")
    assert {status, _headers, _rest} = read_response_head(client)
    assert status in 400..499

    sentinel = connect(ctx.port)
    send_raw(sentinel, "GET /sentinel HTTP/1.1\r\nHost: a\r\n\r\n")
    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)
    assert request_line(head) == "GET /sentinel HTTP/1.1"
  end
end
