defmodule DawarichWeb.NativeM6Envelope do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _) do
    conn =
      register_before_send(conn, fn response ->
        response
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
      end)

    cond do
      conn.method not in ~w(GET HEAD) ->
        refuse(conn, 405)

      conn.query_params["format"] not in [nil, "html"] ->
        refuse(conn, 422)

      Enum.any?(
        get_req_header(conn, "x-requested-with"),
        &(String.downcase(&1) == "xmlhttprequest")
      ) ->
        refuse(conn, 422)

      true ->
        conn
    end
  end

  defp refuse(conn, status),
    do: conn |> put_resp_header("cache-control", "no-store") |> send_resp(status, "") |> halt()
end
