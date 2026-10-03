defmodule Dawarich.Storage.HttpDownloadTest do
  use ExUnit.Case, async: true
  alias Dawarich.Storage.HttpDownload
  alias Dawarich.Test.{DownloadServer, RawHTTP}

  test "delivers chunk bytes before the HTTP response completes" do
    parent = self()

    {url, server} =
      DownloadServer.start(fn socket, head, _ ->
        assert RawHTTP.request_line(head) == "GET /trace?key=synthetic HTTP/1.1"
        RawHTTP.reply(socket, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhe\r\n")

        receive do: (:finish -> RawHTTP.reply(socket, "3\r\nllo\r\n0\r\n\r\n"))
      end)

    client =
      Task.async(fn ->
        HttpDownload.stream!(url <> "/trace?key=synthetic", fn chunk ->
          send(parent, {:chunk, chunk})
        end)
      end)

    receive do: ({:chunk, "he"} -> :ok)
    send(server.pid, :finish)
    assert :ok = Task.await(client, :infinity)
    assert_received {:chunk, "llo"}
    Task.await(server, :infinity)
  end

  test "rejects an HTTP error before receiving its body" do
    {url, server} =
      DownloadServer.start(fn socket, _, _ ->
        RawHTTP.reply(socket, "HTTP/1.1 404 Missing\r\nContent-Length: 999999999\r\n\r\n")
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, :infinity)
      end)

    assert_raise RuntimeError, ~r/HTTP 404/, fn ->
      HttpDownload.stream!(url <> "/missing?X-Amz-Signature=secret", fn _ ->
        flunk("error body delivered")
      end)
    end

    Task.await(server, :infinity)
  end

  test "refuses redirects instead of changing the signed destination" do
    destination = RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(destination.listen) end)

    {url, server} =
      DownloadServer.start(fn socket, _, _ ->
        RawHTTP.reply(
          socket,
          "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:#{destination.port}/secret\r\nContent-Length: 0\r\n\r\n"
        )
      end)

    error =
      assert_raise RuntimeError, fn ->
        HttpDownload.stream!(url <> "/blob?token=private", fn _ -> :ok end)
      end

    assert Exception.message(error) =~ "HTTP 302"
    refute Exception.message(error) =~ "private"
    assert {:error, :timeout} = :gen_tcp.accept(destination.listen, 50)
    Task.await(server, :infinity)
  end

  test "fails an abruptly truncated response" do
    {url, server} =
      DownloadServer.start(fn socket, _, _ ->
        RawHTTP.reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhe")
      end)

    assert_raise RuntimeError, ~r/transport/, fn -> HttpDownload.stream!(url, fn _ -> :ok end) end
    Task.await(server, :infinity)
  end

  test "sink errors close the HTTP socket" do
    {url, server} =
      DownloadServer.start(fn socket, _, _ ->
        RawHTTP.reply(
          socket,
          "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n"
        )

        assert {:error, :closed} = :gen_tcp.recv(socket, 0, :infinity)
      end)

    assert_raise ArgumentError, "sink failed", fn ->
      HttpDownload.stream!(url, fn _ -> raise ArgumentError, "sink failed" end)
    end

    Task.await(server, :infinity)
  end
end
