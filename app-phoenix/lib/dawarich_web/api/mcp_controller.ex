defmodule DawarichWeb.Api.McpController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Mcp.Transport
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, :handle) do
    conn = fetch_query_params(conn)

    case Transport.authorize(conn.req_headers, conn.query_params) do
      {:ok, user} ->
        case body(conn) do
          {:ok, raw, conn} ->
            case Transport.request(conn.method, conn.req_headers, raw, user) do
              {202, nil} -> Respond.head(conn, 202, "application/json")
              {status, term} -> Respond.json(conn, status, term)
            end

          {_, conn} ->
            Respond.json(conn, 413, %{"error" => "Payload too large"})
        end

      {:error, 401} ->
        Respond.head(conn, 401)

      {:error, status} ->
        Respond.json(conn, status, %{"error" => "MCP request rejected"})
    end
  end

  defp body(%{private: %{dawarich_raw_body: raw}} = conn), do: {:ok, raw, conn}
  defp body(conn), do: read_body(conn, length: 4 * 1024 * 1024, read_length: 4 * 1024 * 1024)
end
