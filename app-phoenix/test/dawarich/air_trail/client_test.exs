defmodule Dawarich.AirTrail.ClientTest do
  use ExUnit.Case, async: false

  alias Dawarich.AirTrail.Client
  alias Dawarich.AirTrailStub
  alias Dawarich.Test.RawHTTP

  defp source(url), do: %{url: url, api_key: "k", skip_ssl_verification: false}

  defp tls_redirect do
    cert = [key: {:namedCurve, :secp256r1}, digest: :sha256]

    %{server_config: config} =
      :public_key.pkix_test_data(%{
        server_chain: %{root: cert, peer: cert},
        client_chain: %{root: cert, peer: cert}
      })

    {:ok, listen} = :ssl.listen(0, [ip: {127, 0, 0, 1}, active: false, reuseaddr: true] ++ config)
    {:ok, {_ip, port}} = :ssl.sockname(listen)
    {listen, AirTrailStub.redirect("https://127.0.0.1:#{port}/api/flight/list?scope=mine")}
  end

  test "GETs /api/flight/list?scope=mine with the bearer key and returns the flights" do
    base = AirTrailStub.start(self(), 200, ~s({"success":true,"flights":[{"id":1}]}))

    assert Client.flights(source(base)) == {:ok, [%{"id" => 1}]}
    assert_received {:airtrail_request, "/api/flight/list", "scope=mine", ["Bearer k"]}
  end

  test "strips exactly one trailing slash like Ruby's chomp" do
    base = AirTrailStub.start(self(), 200, ~s({"success":true}))

    assert Client.flights(source(base <> "/")) == {:ok, []}
    assert_received {:airtrail_request, "/api/flight/list", _, _}

    assert Client.flights(source(base <> "//")) == {:ok, []}
    assert_received {:airtrail_request, "//api/flight/list", _, _}
  end

  test "a missing flights key is an empty list" do
    base = AirTrailStub.start(self(), 200, ~s({"success":true}))

    assert Client.flights(source(base)) == {:ok, []}
  end

  test "non-2xx is Ruby's message" do
    base = AirTrailStub.start(self(), 503, ~s({"success":true,"flights":[]}))

    assert Client.flights(source(base)) == {:error, "AirTrail responded with 503"}
  end

  test "success false or missing is Ruby's message" do
    unsuccessful = AirTrailStub.start(self(), 200, ~s({"success":false,"flights":[]}))
    missing = AirTrailStub.start(self(), 200, ~s({}))

    assert Client.flights(source(unsuccessful)) ==
             {:error, "AirTrail returned an unsuccessful response"}

    assert Client.flights(source(missing)) ==
             {:error, "AirTrail returned an unsuccessful response"}
  end

  test "invalid JSON" do
    base = AirTrailStub.start(self(), 200, "nope")

    assert Client.flights(source(base)) == {:error, "AirTrail returned invalid JSON"}
  end

  test "an unreachable host" do
    assert Client.flights(source("http://127.0.0.1:1")) ==
             {:error, "Could not connect to AirTrail"}
  end

  test "an http URL redirected to https still verifies the certificate" do
    {listen, base} = tls_redirect()
    task = Task.async(fn -> Client.flights(source(base)) end)

    {:ok, socket} = :ssl.transport_accept(listen, 5_000)
    assert {:error, {:tls_alert, {:unknown_ca, _}}} = :ssl.handshake(socket, 5_000)
    assert Task.await(task) == {:error, "Could not connect to AirTrail"}
  end

  test "skip_ssl_verification still skips verification after a redirect to https" do
    {listen, base} = tls_redirect()
    task = Task.async(fn -> Client.flights(%{source(base) | skip_ssl_verification: true}) end)

    {:ok, socket} = :ssl.transport_accept(listen, 5_000)
    {:ok, socket} = :ssl.handshake(socket, 5_000)
    {:ok, _request} = :ssl.recv(socket, 0, 5_000)
    :ok = :ssl.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 16\r\n\r\n{\"success\":true}")

    assert Task.await(task) == {:ok, []}
  end

  test "asks AirTrail to close the connection so no keep-alive session is reused" do
    server = RawHTTP.listen()
    task = Task.async(fn -> Client.flights(source("http://127.0.0.1:#{server.port}")) end)

    socket = RawHTTP.accept(server)
    {head, _rest} = RawHTTP.read_head(socket)
    RawHTTP.reply(socket, "HTTP/1.1 200 OK\r\ncontent-length: 16\r\n\r\n{\"success\":true}")

    assert Task.await(task) == {:ok, []}
    assert RawHTTP.header(head, "connection") == ["close"]
  end
end
