defmodule DawarichWeb.TurboVisit do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  @reload ~s(<!DOCTYPE html><html><head><meta name="turbo-visit-control" content="reload"></head><body></body></html>)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{private: %{dawarich_page_envelope: true}} = conn, _opts), do: conn

  def call(conn, _opts) do
    case get_req_header(conn, "x-turbo-request-id") do
      [] ->
        conn

      _ ->
        reload(conn)
    end
  end

  def live_view_visit?(conn) do
    conn.method in ["GET", "HEAD"] and
      get_req_header(conn, "x-dawarich-liveview") == ["true"] and
      Enum.all?(get_req_header(conn, "turbo-frame"), &(String.trim(&1) == "")) and
      DawarichWeb.Strangler.page_request?(conn)
  end

  def reload(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, @reload)
    |> halt()
  end
end
