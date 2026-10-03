defmodule DawarichWeb.VisitsNavigation do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.RequestURL

  @impl true
  def init(opts), do: opts
  @impl true
  def call(conn, _opts) do
    status = Plug.Conn.Query.decode(conn.query_string)["status"] || "confirmed"

    conn
    |> put_resp_header(
      "location",
      RequestURL.base(conn) <>
        "/map/v2?panel=timeline&date=today&status=" <> URI.encode_www_form(status)
    )
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
  end
end
