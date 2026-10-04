defmodule DawarichWeb.MapDataHeaders do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    accept = conn |> get_req_header("accept") |> Enum.join(", ")

    if List.first(conn.path_info) in ["points", "tags"] and String.trim(accept) != "" and
         not DawarichWeb.Strangler.browser_like?(accept) do
      register_before_send(conn, fn conn ->
        if conn.status == 200, do: put_resp_header(conn, "vary", "Accept"), else: conn
      end)
    else
      conn
    end
  end
end
