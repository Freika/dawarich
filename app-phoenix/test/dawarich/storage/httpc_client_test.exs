defmodule Dawarich.Storage.HttpcClientTest do
  use ExUnit.Case, async: true

  alias Dawarich.Storage.HttpcClient
  alias Dawarich.Test.RawHTTP

  test "a killed caller cancels its pending HTTP request" do
    server = RawHTTP.listen()

    caller =
      spawn(fn ->
        HttpcClient.request(:get, "http://127.0.0.1:#{server.port}/blocked", "", [], [])
      end)

    on_exit(fn ->
      Process.exit(caller, :kill)
      :gen_tcp.close(server.listen)
    end)

    socket = RawHTTP.accept(server)
    RawHTTP.read_head(socket)
    ref = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^caller, :killed}
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1_000)
  end

  test "sends method, headers and body over :httpc and returns binary headers" do
    server = RawHTTP.listen()
    url = "http://127.0.0.1:#{server.port}/dawarich/abc?uploadId=up-1"

    task =
      Task.async(fn ->
        HttpcClient.request(
          :put,
          url,
          "part bytes",
          [{"content-md5", "md5=="}, {"x-amz-date", "20260328T000000Z"}],
          []
        )
      end)

    socket = RawHTTP.accept(server)
    {head, rest} = RawHTTP.read_head(socket)
    RawHTTP.read_at_least(socket, rest, 10)

    RawHTTP.reply(
      socket,
      "HTTP/1.1 200 OK\r\nETag: \"etag-1\"\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
    )

    assert {:ok, %{status_code: 200, headers: headers, body: "ok"}} = Task.await(task)
    assert {"etag", ~s("etag-1")} in headers
    assert RawHTTP.request_line(head) == "PUT /dawarich/abc?uploadId=up-1 HTTP/1.1"
    assert RawHTTP.header(head, "content-md5") == ["md5=="]
    assert RawHTTP.header(head, "content-length") == ["10"]
    assert RawHTTP.header(head, "content-type") == ["application/octet-stream"]
  end
end
