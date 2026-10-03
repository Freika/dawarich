defmodule DawarichWeb.InsightsVisit do
  @moduledoc "Preserve actual Turbo details frame GETs while retaining ordinary native visit reloads."
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    frame = conn |> get_req_header("turbo-frame") |> Enum.join(", ") |> String.trim()

    if conn.method in ["GET", "HEAD"] and conn.request_path == "/insights/details" and
         frame != "",
       do: conn,
       else: DawarichWeb.TurboVisit.call(conn, opts)
  end
end
