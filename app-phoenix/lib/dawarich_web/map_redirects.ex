defmodule DawarichWeb.MapRedirects do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.Params

  def init(action), do: action

  def call(conn, action) do
    query =
      if action == :legacy,
        do: conn.query_string |> Plug.Conn.Query.decode() |> Params.to_query(),
        else: ""

    location = DawarichWeb.RequestURL.base(conn) <> "/map/v2"
    location = if query == "", do: location, else: location <> "?" <> query
    conn |> put_resp_header("location", location) |> send_resp(301, "")
  rescue
    Plug.Conn.InvalidQueryError -> send_resp(conn, 400, "")
  end
end
