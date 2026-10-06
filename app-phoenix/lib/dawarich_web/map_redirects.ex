defmodule DawarichWeb.MapRedirects do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{ForceSSL, HostAuthorization, Params, RailsHeaders, RateLimit}

  def init(action), do: action

  def call(conn, action) do
    conn = conn |> HostAuthorization.call([]) |> ForceSSL.call([]) |> RateLimit.call([])

    if conn.halted do
      conn
    else
      query =
        if action == :legacy,
          do: conn.query_string |> Plug.Conn.Query.decode() |> Params.to_query(),
          else: ""

      location = "#{conn.scheme}://#{conn.host}" <> port(conn) <> "/map/v2"
      location = if query == "", do: location, else: location <> "?" <> query
      conn |> RailsHeaders.call([]) |> put_resp_header("location", location) |> send_resp(301, "")
    end
  rescue
    Plug.Conn.InvalidQueryError -> send_resp(conn, 400, "")
  end

  defp port(%{scheme: :http, port: 80}), do: ""
  defp port(%{scheme: :https, port: 443}), do: ""
  defp port(conn), do: ":#{conn.port}"
end
