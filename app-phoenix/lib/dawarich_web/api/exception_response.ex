defmodule DawarichWeb.Api.ExceptionResponse do
  @moduledoc false
  import Plug.Conn

  @reasons %{400 => "Bad Request", 404 => "Not Found", 500 => "Internal Server Error"}

  def send(conn, status) do
    conn = assign(conn, :api_params, conn.assigns[:api_params] || %{})

    elapsed =
      System.convert_time_unit(
        System.monotonic_time() - (conn.assigns[:api_started] || System.monotonic_time()),
        :native,
        :microsecond
      )
      |> max(0)

    conn =
      conn
      |> put_resp_header("x-request-id", conn.assigns[:api_request_id] || Ecto.UUID.generate())
      |> put_resp_header("x-runtime", :erlang.float_to_binary(elapsed / 1_000_000, decimals: 6))

    case DawarichWeb.Api.RequestFormat.decide(conn) do
      {:ok, :json, _} ->
        body =
          DawarichWeb.Api.Respond.encode(
            {:object, [{"status", status}, {"error", @reasons[status]}]}
          )

        conn
        |> put_resp_header("content-type", "application/json; charset=UTF-8")
        |> delete_resp_header("cache-control")
        |> send_resp(status, body)
        |> halt()

      _ ->
        DawarichWeb.RailsErrors.respond(conn, status)
    end
  end

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
