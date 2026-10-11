defmodule Dawarich.Test.NativeDrainPlug do
  @behaviour Plug
  def init(opts), do: opts

  def call(conn, opts) do
    send(opts[:owner], {:request_waiting, self()})

    receive do
      :finish -> Plug.Conn.send_resp(conn, 200, "done")
    after
      10_000 -> Plug.Conn.send_resp(conn, 503, "timeout")
    end
  end
end
