defmodule DawarichWeb.VisitsNavigation do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.RequestURL

  @impl true
  def init(opts), do: opts
  @impl true
  def call(conn, _opts) do
    if DawarichWeb.A8Gate.scalar_query?(conn.query_string, ~w(status locale)) do
      navigate(conn)
    else
      conn |> send_resp(422, "") |> halt()
    end
  end

  defp navigate(conn) do
    status = Plug.Conn.Query.decode(conn.query_string)["status"] || "confirmed"

    conn
    |> put_resp_header(
      "location",
      RequestURL.base(conn) <>
        "/map/v2?panel=timeline&date=today&status=" <> URI.encode_www_form(status)
    )
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("content-type", "text/html; charset=UTF-8")
    |> send_resp(302, "")
  end
end
