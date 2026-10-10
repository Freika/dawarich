defmodule Dawarich.Imports.TeslamateClientTest do
  use ExUnit.Case, async: true
  import Dawarich.Test.RawHTTP
  alias Dawarich.Imports.Teslamate.{Client, Point}

  test "teslamate API points preserve units battery tracker and raw data" do
    for {name, auth} <- [{"success", :basic}, {"km", :bearer}] do
      expected = fixture(name)
      server = listen()
      on_exit(fn -> :gen_tcp.close(server.listen) end)
      task = Task.async(fn -> responses(server, expected["requests"], auth) end)

      options =
        if auth == :basic,
          do: [
            username: "synthetic-user",
            password: "synthetic-pass",
            api_token: "synthetic-token"
          ],
          else: [api_token: "synthetic-token"]

      client = Client.new("http://127.0.0.1:#{server.port}/", options)
      assert {:ok, [%{"car_id" => 1}]} = Client.cars(client)

      assert {:ok, %{drives: [%{"drive_id" => 11}], units: units}} =
               Client.drives(client, 1, page: 1, show: 100, end_date: ~U[2026-01-15 23:30:00Z])

      assert {:ok, result} = Client.drive(client, 1, 11)
      assert {:ok, [point], 1} = Point.prepare_drive(result, 1, 11, units)
      captured = hd(expected["points"])

      for key <- ~w(lonlat timestamp altitude battery tracker_id raw_data) do
        assert point[String.to_existing_atom(key)] == captured[key]
      end

      assert point.altitude_decimal == String.to_float(captured["altitude_decimal"])
      assert point.velocity == String.to_float(captured["velocity"])
      assert point.external_track_id == "teslamate-drive-11"
      assert {:ok, [^point], 1} = Point.prepare_drive(%{result | units: %{}}, 1, 11, units)
      [detail | _] = result.drive["drive_details"]

      assert {:ok, %{battery: 0}} =
               Point.prepare(Map.put(detail, "usable_battery_level", 0), 1, 11, units)

      for invalid <- [
            nil,
            [],
            Map.put(detail, "latitude", "NaN"),
            Map.put(detail, "longitude", 181),
            Map.put(detail, "date", "invalid")
          ] do
        assert :skip = Point.prepare(invalid, 1, 11, units)
      end

      assert {:ok, %{velocity: nil}} =
               Point.prepare(Map.put(detail, "speed", "Infinity"), 1, 11, %{})

      assert {:error, "unsupported length unit: missing"} = Point.prepare(detail, 1, 11, %{})
      Task.await(task)
    end

    for skip <- [false, true] do
      cert = [key: {:namedCurve, :secp256r1}, digest: :sha256]

      %{server_config: config} =
        :public_key.pkix_test_data(%{
          server_chain: %{root: cert, peer: cert},
          client_chain: %{root: cert, peer: cert}
        })

      {:ok, listener} =
        :ssl.listen(0, [ip: {127, 0, 0, 1}, active: false, reuseaddr: true] ++ config)

      on_exit(fn -> :ssl.close(listener) end)
      {:ok, {_, port}} = :ssl.sockname(listener)

      client =
        Client.new("https://127.0.0.1:#{port}", skip_ssl_verification: skip, max_attempts: 1)

      task = Task.async(fn -> Client.cars(client) end)
      {:ok, socket} = :ssl.transport_accept(listener, 5_000)

      if skip do
        {:ok, socket} = :ssl.handshake(socket, 5_000)
        {:ok, request} = :ssl.recv(socket, 0, 5_000)
        assert String.starts_with?(to_string(request), "GET /api/v1/cars HTTP/1.1")
        body = ~s({"data":{"cars":null}})

        :ok =
          :ssl.send(
            socket,
            "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <>
              body
          )

        assert Task.await(task) == {:ok, []}
        :ssl.close(socket)
      else
        assert {:error, {:tls_alert, {:unknown_ca, _}}} = :ssl.handshake(socket, 5_000)
        assert Task.await(task) == {:error, "TeslaMateApi connection failed"}
      end
    end
  end

  test "teslamate missing drive_details is an incomplete response" do
    expected = fixture("incomplete")
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    task = Task.async(fn -> responses(server, expected["requests"], :none) end)
    client = Client.new("http://127.0.0.1:#{server.port}")
    assert {:ok, [_]} = Client.cars(client)

    assert {:ok, %{units: units}} =
             Client.drives(client, 1, page: 1, show: 100, end_date: ~U[2026-01-15 23:30:00Z])

    assert {:ok, result} = Client.drive(client, 1, 11)
    assert {:error, message} = Point.prepare_drive(result, 1, 11, units)

    assert expected["error"]["message"] ==
             "TeslaMateApi sync incomplete: car 1, drive 11: " <> message

    assert {:ok, [], 0} =
             Point.prepare_drive(%{drive: %{"drive_details" => nil}, units: %{}}, 1, 11)

    assert {:error, ^message} =
             Point.prepare_drive(%{drive: %{"drive_details" => %{}}, units: %{}}, 1, 11)

    Task.await(task)

    assert {:error, "TeslaMateApi resource ID must be a positive integer"} =
             Client.drive(client, 1, "../2")

    assert {:error, "TeslaMateApi page must be a positive integer"} =
             Client.drives(client, 1, page: 1.5, show: 100, end_date: ~U[2026-01-15 23:30:00Z])

    for {body, error} <- [
          {"invalid", "TeslaMateApi returned an invalid response"},
          {"{}", "TeslaMateApi returned an invalid response"},
          {~s({"data":{},"error":"synthetic-error"}), "synthetic-error"},
          {~s({"data":{}}), "TeslaMateApi response did not contain cars data"}
        ] do
      task =
        Task.async(fn ->
          responses(server, [%{"path" => "/api/v1/cars", "query" => %{}, "body" => body}], :none)
        end)

      assert {:error, ^error} = Client.cars(client)
      Task.await(task)
    end

    task =
      Task.async(fn ->
        responses(
          server,
          [
            %{"path" => "/api/v1/cars", "query" => %{}, "body" => "{}", "status" => 503},
            %{"path" => "/api/v1/cars", "query" => %{}, "body" => ~s({"data":{"cars":null}})}
          ],
          :none
        )
      end)

    assert {:ok, []} = Client.cars(client)
    Task.await(task)

    task =
      Task.async(fn ->
        responses(
          server,
          [
            %{"path" => "/api/v1/cars", "query" => %{}, "body" => "{}", "status" => 401}
          ],
          :none
        )
      end)

    assert {:error, "TeslaMateApi responded with 401"} = Client.cars(client)
    Task.await(task)

    task =
      Task.async(fn ->
        responses(
          server,
          [
            %{"path" => "//api/v1/cars", "query" => %{}, "body" => ~s({"data":{"cars":[]}})}
          ],
          :none
        )
      end)

    assert {:error, "TeslaMateApi connection failed"} =
             Client.cars(Client.new("http://127.0.0.1:#{server.port}//"))

    Task.shutdown(task, :brutal_kill)
  end

  defp fixture(name) do
    Path.expand("../../fixtures/imports/formats/producers/teslamate/#{name}.json", __DIR__)
    |> File.read!()
    |> Jason.decode!()
  end

  defp responses(server, requests, auth) do
    Enum.each(requests, fn expected ->
      socket = accept(server)
      {head, _} = read_head(socket)
      ["GET", path, _] = String.split(request_line(head))
      uri = URI.parse("http://127.0.0.1" <> path)
      assert uri.path == expected["path"]

      assert URI.decode_query(uri.query || "") |> Map.new(fn {k, v} -> {k, [v]} end) ==
               expected["query"]

      assert header(head, "accept") == ["application/json"]

      expected_auth =
        case auth do
          :basic -> ["Basic " <> Base.encode64("synthetic-user:synthetic-pass")]
          :bearer -> ["Bearer synthetic-token"]
          :none -> []
        end

      assert header(head, "authorization") == expected_auth
      body = expected["body"]

      status = expected["status"] || 200

      reply(
        socket,
        "HTTP/1.1 #{status} OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
          body
      )

      :gen_tcp.close(socket)
    end)
  end
end
