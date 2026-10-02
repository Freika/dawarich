defmodule DawarichWeb.ImportsRequest do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    conn =
      conn |> fetch_query_params() |> put_resp_header("x-dawarich-handler", "phoenix-imports")

    conn =
      if conn.method == "PUT",
        do: conn,
        else:
          Plug.Parsers.call(
            conn,
            Plug.Parsers.init(
              parsers: [:urlencoded, :json],
              pass: ["*/*"],
              json_decoder: Jason,
              length: 2_097_152
            )
          )

    cond do
      is_nil(conn.assigns.current_user) ->
        reject(conn, 401, "unauthorized")

      Enum.any?(~w(cookie x-csrf-token origin), &(length(get_req_header(conn, &1)) > 1)) ->
        reject(conn, 422, "ambiguous headers")

      get_req_header(conn, "origin") not in [[], [DawarichWeb.RequestURL.base(conn)]] ->
        reject(conn, 422, "origin")

      conn.method == "PUT" ->
        conn

      valid_csrf?(conn) ->
        conn

      true ->
        reject(conn, 422, "authenticity token")
    end
  rescue
    Plug.Parsers.ParseError -> reject(conn, 422, "invalid request")
    Plug.Parsers.RequestTooLargeError -> reject(conn, 413, "request too large")
  end

  defp valid_csrf?(conn) do
    tokens = [conn.params["authenticity_token"] | get_req_header(conn, "x-csrf-token")]
    Enum.any?(tokens, &DawarichWeb.RailsCsrf.valid?(conn.assigns.rails_session, &1))
  end

  defp reject(conn, status, error),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(%{error: error}))
      |> halt()
end
