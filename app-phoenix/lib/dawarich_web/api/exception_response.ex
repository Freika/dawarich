defmodule DawarichWeb.Api.ExceptionResponse do
  @moduledoc false
  import Plug.Conn

  def respond(conn, status) do
    conn =
      Enum.reduce(conn.resp_headers, conn, fn {key, _}, conn -> delete_resp_header(conn, key) end)

    conn
    |> put_resp_header("x-request-id", conn.assigns.api_request_id)
    |> put_resp_header("x-runtime", "0.000000")
    |> register_before_send(
      &put_resp_header(&1, "content-type", "application/json; charset=UTF-8")
    )
    |> DawarichWeb.RailsErrors.respond(status, transport: true)
  end
end
