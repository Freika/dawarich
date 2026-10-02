defmodule DawarichWeb.ImportsHeaders do
  @moduledoc false
  @behaviour Plug
  def init(opts), do: opts

  def call(conn, _) do
    if conn.path_info |> List.first() == "imports",
      do: Plug.Conn.put_resp_header(conn, "x-dawarich-handler", "phoenix-imports"),
      else: conn
  end
end
