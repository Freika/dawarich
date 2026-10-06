defmodule DawarichWeb.UserDataGate do
  @moduledoc false
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, :decode) do
    case DawarichWeb.A8FormDecode.params(conn, ["archive[]"]) do
      {:ok, conn, params} ->
        query = DawarichWeb.A8FormDecode.urlencoded(conn.query_string)

        conn
        |> assign(:api_query, query)
        |> assign(:api_params, Map.merge(params, query))

      {:replay, conn} ->
        DawarichWeb.Api.Body.replay(conn, "archive request envelope")

      {:error, conn} ->
        halt(conn)
    end
  end

  def native?(conn, _) do
    conn.method in ["GET", "POST"] and DawarichWeb.Strangler.page_request?(conn) and
      (conn.method != "GET" or Plug.Conn.get_req_header(conn, "content-length") in [[], ["0"]])
  end
end
