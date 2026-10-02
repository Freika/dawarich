defmodule Dawarich.Test.DownloadServer do
  @moduledoc false
  alias Dawarich.Test.RawHTTP

  def start(handler, count \\ 1) do
    server = RawHTTP.listen()

    task =
      Task.async(fn ->
        try do
          for index <- 1..count do
            socket = RawHTTP.accept(server)

            try do
              {head, _} = RawHTTP.read_head(socket)
              handler.(socket, head, index)
            after
              :gen_tcp.close(socket)
            end
          end
        after
          :gen_tcp.close(server.listen)
        end
      end)

    {"http://127.0.0.1:#{server.port}", task}
  end

  def hello(socket) do
    RawHTTP.reply(
      socket,
      "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"
    )
  end
end
