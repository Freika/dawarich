defmodule DawarichWeb.NativeMapRetired do
  @moduledoc false
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.put_resp_header("cache-control", "no-store")
    |> Plug.Conn.send_resp(410, "This map command is available through the native map.")
    |> Plug.Conn.halt()
  end
end
