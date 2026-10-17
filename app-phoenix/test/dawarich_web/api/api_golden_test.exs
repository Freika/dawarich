defmodule Dawarich.Test.ApiGoldenTest do
  use ExUnit.Case, async: true

  import Dawarich.Test.RawHTTP

  alias Dawarich.Test.ApiGolden

  test "former hand-back cases compare terminal Rails status headers and body without upstream effects" do
    expected = %{
      "status" => 200,
      "headers" => %{
        "content-type" => "application/json; charset=utf-8",
        "x-request-id" => "00000000-0000-0000-0000-000000000000",
        "x-runtime" => "0.000001"
      },
      "body" => ~s({"ok":true})
    }

    check(expected, expected)

    for changed <- [
          Map.put(expected, "status", 422),
          Map.put(expected, "body", ~s({"ok":false})),
          put_in(expected, ["headers", "content-type"], "text/plain"),
          update_in(expected, ["headers"], &Map.put(&1, "x-extra", "unexpected"))
        ] do
      assert_raise ExUnit.AssertionError, fn -> check(expected, changed) end
    end
  end

  test "signed error bodies validate original framing without inventing an ETag" do
    expected = %{
      "status" => 403,
      "headers" => %{
        "content-type" => "application/json",
        "x-request-id" => "00000000-0000-0000-0000-000000000000",
        "x-runtime" => "0.000001"
      },
      "body" => ~s({"token":"redacted"})
    }

    actual = Map.put(expected, "body", ~s({"token":"verified-synthetic-token"}))

    validator = fn raw ->
      assert {:ok, decoded} = Jason.decode(raw)
      assert decoded["token"] == "verified-synthetic-token"
      String.replace(raw, "verified-synthetic-token", "redacted")
    end

    options = [crypto: validator, crypto_etag: false]
    check(expected, actual, options)

    for changed <- [
          Map.put(actual, "body", ~s({"token":"invalid"})),
          Map.put(actual, "length", byte_size(actual["body"]) - 1),
          put_in(actual, ["headers", "etag"], "unexpected")
        ] do
      assert_raise ExUnit.AssertionError, fn -> check(expected, changed, options) end
    end
  end

  defp check(expected, actual, options \\ []) do
    server = listen()
    upstream = listen()

    peer =
      Task.async(fn ->
        socket = accept(server)
        read_head(socket)

        reply(socket, [
          "HTTP/1.1 #{actual["status"]} OK\r\n",
          Enum.map(actual["headers"], fn {name, value} -> "#{name}: #{value}\r\n" end),
          "Content-Length: #{actual["length"] || byte_size(actual["body"])}\r\n\r\n",
          actual["body"]
        ])

        :gen_tcp.close(socket)
      end)

    try do
      ApiGolden.check(
        %{
          "expect" => "rails",
          "request" => %{"method" => "GET", "target" => "/api/v1/test", "headers" => []},
          "response" => expected
        },
        server.port,
        upstream,
        options
      )
    after
      Task.await(peer)
      :gen_tcp.close(server.listen)
      :gen_tcp.close(upstream.listen)
    end
  end
end
