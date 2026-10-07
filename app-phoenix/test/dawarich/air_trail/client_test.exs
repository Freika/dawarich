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
    on_exit(fn -> :ssl.close(listen) end)
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

    assert Client.flights(source(base <> "//")) == {:error, "AirTrail request failed"}
    refute_received {:airtrail_request, "//api/flight/list", _, _}
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

  @tag :airtrail_redirect_verified
  test "AirTrail refuses a cross-host HTTPS redirect with certificate verification enabled" do
    assert_redirect_refused(false)
  end

  @tag :airtrail_redirect_skipped
  test "AirTrail refuses a cross-host HTTPS redirect even when certificate verification is skipped" do
    assert_redirect_refused(true)
  end

  defp assert_redirect_refused(skip) do
    {listen, base} = tls_redirect()
    parent = self()
    ref = make_ref()

    target =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listen, :infinity)
        send(parent, {ref, :contacted})

        case :ssl.handshake(socket, :infinity) do
          {:ok, socket} ->
            :ssl.recv(socket, 0, :infinity)
            :ssl.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 16\r\n\r\n{\"success\":true}")
            :ssl.close(socket)

          {:error, _} ->
            :ok
        end
      end)

    result = Client.flights(%{source(base) | skip_ssl_verification: skip})
    Task.shutdown(target, :brutal_kill)
    refute_received {^ref, :contacted}
    assert result == {:error, "AirTrail responded with 302"}
  end

  test "asks AirTrail to close the connection so no keep-alive session is reused" do
    server = RawHTTP.listen()
    base = "http://127.0.0.1:#{server.port}"
    response = "HTTP/1.1 200 OK\r\ncontent-length: 16\r\n\r\n{\"success\":true}"

    warmup =
      Task.async(fn ->
        :httpc.request(:get, {String.to_charlist(base), []}, [], body_format: :binary)
      end)

    pooled_socket = RawHTTP.accept(server)
    RawHTTP.read_head(pooled_socket)
    RawHTTP.reply(pooled_socket, response)
    assert {:ok, _} = Task.await(warmup, :infinity)
    owner = self()
    ref = make_ref()

    fresh =
      Task.async(fn ->
        socket = RawHTTP.accept(server)
        {head, _} = RawHTTP.read_head(socket)
        send(owner, {ref, :fresh, head})
        RawHTTP.reply(socket, response)
      end)

    pooled =
      Task.async(fn ->
        {head, _} = RawHTTP.read_head(pooled_socket)
        send(owner, {ref, :pooled, head})
        RawHTTP.reply(pooled_socket, response)
      end)

    try do
      assert Client.flights(source(base)) == {:ok, []}
      assert_received {^ref, :fresh, head}
      assert RawHTTP.header(head, "connection") == ["close"]
    after
      Task.shutdown(fresh, :brutal_kill)
      Task.shutdown(pooled, :brutal_kill)
      :gen_tcp.close(pooled_socket)
      :gen_tcp.close(server.listen)
    end
  end
end
