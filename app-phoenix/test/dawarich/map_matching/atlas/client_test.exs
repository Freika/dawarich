defmodule Dawarich.MapMatching.Atlas.ClientTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import Dawarich.Test.RawHTTP
  alias Dawarich.MapMatching.Atlas.{Client, ConnectionTest, Endpoint}

  @input %{shape: [%{lat: 52.512345, lon: 13.412345, time: 100, accuracy: 5}], costing: "bicycle"}
  @geometry %{"type" => "LineString", "coordinates" => [[13.4, 52.5], [13.41, 52.51]]}
  @match %{
    "data" => %{"geometry" => @geometry, "stats" => %{"matched" => 2}},
    "meta" => %{"mode" => "bicycle"}
  }
  @health %{"data" => %{"status" => "degraded", "capabilities" => %{"routing" => "up"}}}
  @version %{"data" => %{"version" => "0.6.0", "revision" => "abcdef1234567890"}}

  setup do
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    %{server: server, url: "http://localhost:#{server.port}"}
  end

  test "reads health and routing readiness", c do
    task = serve(c.server, [{200, @health, []}])
    assert {:ok, %{status: "degraded", routing: "up"}} = Client.health(c.url)
    assert [{"GET /api/v1/health HTTP/1.1", _, ""}] = Task.await(task)
  end

  test "reads version and optional revision", c do
    task =
      serve(c.server, [
        {200, @version, []},
        {200, %{"data" => %{"version" => "0.6.0"}}, []},
        {200, %{"data" => %{"version" => "0.6.0", "revision" => " \t "}}, []}
      ])

    assert {:ok, %{version: "0.6.0", revision: "abcdef1234567890"}} = Client.version(c.url)
    assert {:ok, %{version: "0.6.0", revision: nil}} = Client.version(c.url)
    assert {:ok, %{version: "0.6.0", revision: nil}} = Client.version(c.url)
    assert [{"GET /api/v1/version HTTP/1.1", _, ""}, _, _] = Task.await(task)
  end

  test "request uses shape_match=map_snap, format=geojson, include_directions=false", c do
    task = serve(c.server, [{200, @match, []}])

    assert {:ok,
            %{geometry: @geometry, stats: %{"matched" => 2}, provider: %{"mode" => "bicycle"}}} =
             Client.match(c.url, @input)

    assert [{"POST /api/v1/map-match HTTP/1.1", head, body}] = Task.await(task)
    assert header(head, "accept") == ["application/json"]
    assert header(head, "content-type") == ["application/json"]

    assert Jason.decode!(body) == %{
             "mode" => "bicycle",
             "shape" => [
               %{"lat" => 52.512345, "lon" => 13.412345, "time" => 100, "accuracy" => 5}
             ],
             "shape_match" => "map_snap",
             "format" => "geojson",
             "include_directions" => false
           }
  end

  test "422 is terminal", c do
    task =
      serve(
        c.server,
        for(status <- [400, 422], do: {status, "coordinate 52.512345,13.412345", []})
      )

    for status <- [400, 422] do
      assert {:error,
              %{
                __struct__: Client.Error,
                code: "invalid_input",
                status: ^status,
                transient?: false,
                retry_after: nil
              } = error} = Client.match(c.url, @input)

      refute inspect(error) =~ "52.512345"
      refute inspect(error) =~ "13.412345"
    end

    Task.await(task)
  end

  test "429 carries retry_after", c do
    task =
      serve(
        c.server,
        for(value <- ["3", "invalid"], do: {429, "capacity", [{"Retry-After", value}]})
      )

    assert {:error, %{code: "capacity", status: 429, transient?: true, retry_after: 3}} =
             Client.match(c.url, @input)

    assert {:error, %{code: "capacity", transient?: true, retry_after: nil}} =
             Client.match(c.url, @input)

    Task.await(task)
  end

  test "503 and timeout are transient", c do
    task = serve(c.server, [{502, "unavailable", []}, {503, "unavailable", []}])

    for status <- [502, 503] do
      assert {:error, %{code: "unavailable", status: ^status, transient?: true}} =
               Client.match(c.url, @input)
    end

    Task.await(task)
    owner = self()

    task =
      Task.async(fn ->
        socket = accept(c.server)
        read_head(socket)
        send(owner, :request_received)

        receive do
          :close -> :gen_tcp.close(socket)
        end
      end)

    request = Task.async(fn -> Client.match(c.url, @input, receive_timeout: 25) end)
    assert_receive :request_received
    assert {:error, %{code: "connection_failed", transient?: true}} = Task.await(request)
    send(task.pid, :close)
    Task.await(task)
  end

  test "rejects oversized Content-Length responses for every Atlas call", c do
    for {call, payload} <- [{:health, @health}, {:version, @version}, {:match, @match}] do
      body = Jason.encode!(Map.put(payload, "padding", String.duplicate("x", 8 * 1024 * 1024)))
      task = stream_response(c.server, "Content-Length: #{byte_size(body)}", [body])
      result = atlas_call(call, c.url, receive_timeout: 100)
      Task.await(task)

      assert {:error, %Client.Error{code: "response_too_large", transient?: true} = error} =
               result

      assert error.message == "Atlas request failed"
      refute inspect(error) =~ "padding"

      task = stream_response(c.server, "Content-Length: #{byte_size(body)}", [])
      result = atlas_call(call, c.url, receive_timeout: 100)
      assert Task.await(task) == {:error, :closed}
      assert {:error, %Client.Error{code: "response_too_large"}} = result

      base = Jason.encode!(Map.put(payload, "padding", ""))

      body =
        Jason.encode!(
          Map.put(payload, "padding", String.duplicate("x", 8 * 1024 * 1024 - byte_size(base)))
        )

      task = stream_response(c.server, "Content-Length: #{byte_size(body)}", [body])
      result = atlas_call(call, c.url, receive_timeout: 100)
      Task.await(task)
      assert {:ok, _} = result
    end
  end

  test "rejects oversized streams without Content-Length before completion", c do
    for framing <- [:chunked, :close],
        {call, payload} <- [{:health, @health}, {:version, @version}, {:match, @match}] do
      body = Jason.encode!(Map.put(payload, "padding", String.duplicate("x", 8 * 1024 * 1024)))
      headers = if framing == :chunked, do: "Transfer-Encoding: chunked", else: ""
      data = if framing == :chunked, do: chunk(body), else: body
      task = stream_response(c.server, headers, [data])
      result = atlas_call(call, c.url, receive_timeout: 100)
      assert Task.await(task) == {:error, :closed}
      assert {:error, %Client.Error{code: "response_too_large", transient?: true}} = result
    end

    task =
      stream_response(
        c.server,
        "Transfer-Encoding: chunked",
        [chunk(String.duplicate("x", 8 * 1024 * 1024 + 1))],
        503
      )

    result = Client.health(c.url, receive_timeout: 100)
    assert Task.await(task) == {:error, :closed}
    assert {:error, %Client.Error{code: "response_too_large"}} = result
  end

  test "cuts off a drip response at the overall request deadline", c do
    body = Jason.encode!(@health)

    task =
      Task.async(fn ->
        socket = accept(c.server)
        read_head(socket)
        reply(socket, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")

        try do
          Enum.reduce_while(:binary.bin_to_list(body), 0, fn byte, count ->
            case :gen_tcp.send(socket, chunk(<<byte>>)) do
              :ok ->
                Process.sleep(20)

                case :gen_tcp.recv(socket, 0, 0) do
                  {:error, :closed} -> {:halt, count + 1}
                  {:error, :timeout} -> {:cont, count + 1}
                end

              {:error, :closed} ->
                {:halt, count}
            end
          end)
        after
          :gen_tcp.send(socket, "0\r\n\r\n")
          :gen_tcp.close(socket)
        end
      end)

    started = System.monotonic_time(:millisecond)
    result = Client.health(c.url, receive_timeout: 100, request_timeout: 120)
    elapsed = System.monotonic_time(:millisecond) - started
    count = Task.await(task)
    assert {:error, %Client.Error{code: "request_timeout", transient?: true}} = result
    assert count < byte_size(body)
    assert elapsed < 500
  end

  test "connection failure is transient", c do
    :gen_tcp.close(c.server.listen)

    assert {:error, %{code: "connection_failed", status: nil, transient?: true}} =
             Client.health(c.url)
  end

  test "redirect is rejected", c do
    target = listen()
    on_exit(fn -> :gen_tcp.close(target.listen) end)

    task =
      serve(c.server, [{302, "", [{"Location", "http://127.0.0.1:#{target.port}/redirect"}]}])

    assert {:error, %{code: "http_error", status: 302, transient?: false}} = Client.health(c.url)
    Task.await(task)
    assert {:error, :timeout} = :gen_tcp.accept(target.listen, 25)
  end

  test "other HTTP errors remain terminal", c do
    task = serve(c.server, [{500, "secret upstream detail", []}])

    assert {:error, %{code: "http_error", status: 500, transient?: false} = error} =
             Client.health(c.url)

    refute inspect(error) =~ "secret upstream detail"
    Task.await(task)
  end

  test "malformed 2xx is provider_invalid", c do
    invalid = [
      "{not-json",
      "[]",
      "null",
      %{},
      %{"data" => []},
      %{"data" => %{"status" => "up"}},
      %{"data" => %{"status" => 1, "capabilities" => %{"routing" => "up"}}}
    ]

    task = serve(c.server, for(body <- invalid, do: {200, body, []}))

    for _ <- invalid do
      assert {:error, %{code: "provider_invalid", transient?: true}} = Client.health(c.url)
    end

    Task.await(task)
  end

  test "version and match validate successful envelopes", c do
    invalid = [
      put_in(@match, ["data", "geometry"], nil),
      put_in(@match, ["data", "geometry", "type"], "Point"),
      put_in(@match, ["data", "geometry", "coordinates"], []),
      put_in(@match, ["data", "stats"], []),
      Map.delete(@match, "meta")
    ]

    task =
      serve(c.server, [
        {200, %{"data" => %{"version" => nil}}, []},
        {200, %{"data" => %{"version" => "0.6.0", "revision" => %{}}}, []},
        {200, %{"data" => %{"version" => "0.6.0", "revision" => [1, 2]}}, []}
        | for(body <- invalid, do: {200, body, []})
      ])

    for _ <- 1..3 do
      assert {:error, %{code: "provider_invalid", transient?: true}} = Client.version(c.url)
    end

    for _ <- invalid do
      assert {:error, %{code: "provider_invalid", transient?: true}} = Client.match(c.url, @input)
    end

    Task.await(task)
  end

  test "allows private addresses and pins resolution while preserving hostname", c do
    {uri, address} = Endpoint.resolve!(c.url)
    assert uri.host == "localhost"
    assert address == {127, 0, 0, 1}
    task = serve(c.server, [{200, @version, []}])

    tracer =
      Task.async(fn ->
        receive do
          trace -> trace
        end
      end)

    Code.ensure_loaded!(Mint.HTTP)
    :erlang.trace_pattern({Mint.HTTP, :connect, 4}, true, [])
    :erlang.trace(self(), true, [:call, {:tracer, tracer.pid}])

    try do
      assert {:ok, %{version: "0.6.0"}} = Client.version(c.url)

      assert {:trace, _, :call, {Mint.HTTP, :connect, [:http, {127, 0, 0, 1}, _, options]}} =
               Task.await(tracer)

      assert options[:hostname] == "localhost"
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern({Mint.HTTP, :connect, 4}, false, [])
    end

    assert [{_, head, _}] = Task.await(task)
    assert header(head, "host") == ["localhost:#{c.server.port}"]
  end

  test "normalizes base path and trailing slash", c do
    task = serve(c.server, [{200, @version, []}])
    assert {:ok, _} = Client.version("  #{c.url}/atlas///  ")
    assert [{"GET /atlas/api/v1/version HTTP/1.1", _, _}] = Task.await(task)
  end

  test "rejects credentials query fragment and non-http URLs", c do
    for url <- [
          "http://user:secret@localhost:#{c.server.port}",
          c.url <> "?key=secret",
          c.url <> "#secret",
          "ftp://localhost",
          "http:///missing",
          nil,
          "",
          "http://[",
          "http://169.254.169.254"
        ] do
      assert_raise Client.Error, fn -> Endpoint.resolve!(url) end
      assert {:error, %{code: "invalid_url", transient?: false} = error} = Client.health(url)
      refute inspect(error) =~ "secret"
    end
  end

  test "logs never contain request or response bodies", c do
    task =
      serve(c.server, [
        {422, "coordinate 52.512345,13.412345 at 2030-01-01", []},
        {503, "secret upstream detail 52.512345", []}
      ])

    log =
      capture_log(fn ->
        assert {:error, _} = Client.match(c.url, @input)
        assert {:error, "unavailable"} = ConnectionTest.call(c.url)
      end)

    assert log =~ "code=unavailable"
    refute log =~ "52.512345"
    refute log =~ "13.412345"
    refute log =~ "2030-01-01"
    refute log =~ "secret upstream detail"
    Task.await(task)
  end

  test "connection test reports ready routing and version", c do
    task = serve(c.server, [{200, @health, []}, {200, @version, []}])
    assert {:ok, %{version: "0.6.0", revision: "abcdef1234567890"}} = ConnectionTest.call(c.url)

    assert [{"GET /api/v1/health HTTP/1.1", _, _}, {"GET /api/v1/version HTTP/1.1", _, _}] =
             Task.await(task)
  end

  test "connection test reports routing unavailable", c do
    health = put_in(@health, ["data", "capabilities", "routing"], "down")
    task = serve(c.server, [{200, health, []}, {200, @version, []}])
    assert {:error, "routing_unavailable"} = ConnectionTest.call(c.url)
    Task.await(task)
  end

  test "connection test returns sanitized health and version failures", c do
    task =
      serve(c.server, [
        {503, "secret upstream detail", []},
        {200, @health, []},
        {422, "secret upstream detail", []}
      ])

    capture_log(fn ->
      assert {:error, "unavailable"} = ConnectionTest.call(c.url)
      assert {:error, "invalid_input"} = ConnectionTest.call(c.url)
    end)

    Task.await(task)
  end

  test "connection test reports not configured" do
    for url <- [nil, "", "  "] do
      assert {:error, "not_configured"} = ConnectionTest.call(url)
    end
  end

  defp atlas_call(:match, url, opts), do: Client.match(url, @input, opts)
  defp atlas_call(call, url, opts), do: apply(Client, call, [url, opts])

  defp chunk(body), do: [Integer.to_string(byte_size(body), 16), "\r\n", body, "\r\n"]

  defp stream_response(server, headers, fragments, status \\ 200) do
    Task.async(fn ->
      socket = accept(server)
      read_head(socket)

      try do
        :gen_tcp.send(socket, ["HTTP/1.1 #{status} Response\r\n", headers, "\r\n\r\n", fragments])
        :gen_tcp.recv(socket, 0, 1_000)
      after
        :gen_tcp.close(socket)
      end
    end)
  end

  defp serve(server, responses) do
    Task.async(fn ->
      for {status, body, headers} <- responses do
        socket = accept(server)

        try do
          {head, rest} = read_head(socket)

          length =
            case header(head, "content-length") do
              [value] -> String.to_integer(value)
              [] -> 0
            end

          request_body = binary_part(read_at_least(socket, rest, length), 0, length)
          body = if is_binary(body), do: body, else: Jason.encode!(body)

          reply(socket, [
            "HTTP/1.1 #{status} Response\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n",
            Enum.map(headers, fn {key, value} -> "#{key}: #{value}\r\n" end),
            "\r\n",
            body
          ])

          {request_line(head), head, request_body}
        after
          :gen_tcp.close(socket)
        end
      end
    end)
  end
end
