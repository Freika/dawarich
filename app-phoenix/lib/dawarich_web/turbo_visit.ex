defmodule DawarichWeb.TurboVisit do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  @reload ~s(<!DOCTYPE html><html><head><meta name="turbo-visit-control" content="reload"></head><body></body></html>)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_req_header(conn, "x-turbo-request-id") do
      [] ->
        conn

      _ ->
        conn
        |> put_resp_content_type("text/html")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, @reload)
        |> halt()
    end
  end
end
