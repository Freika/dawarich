defmodule DawarichWeb.ImportsHeaders do
  @moduledoc false
  @behaviour Plug
  def init(opts), do: opts

  def call(conn, _) do
    if not conn.halted and List.first(conn.path_info) == "imports",
      do: Plug.Conn.put_resp_header(conn, "x-dawarich-handler", "phoenix-imports"),
      else: conn
  end
end
