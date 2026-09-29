defmodule DawarichWeb.Api.Respond do
  @moduledoc false

  import Plug.Conn

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.RailsHeaders

  def json(conn, status, term) do
    body = term |> Ruby.json() |> IO.iodata_to_binary()
    conn = frame(conn, "application/json; charset=utf-8")
    conn = if conn.assigns.api_vary, do: put_resp_header(conn, "vary", "Accept"), else: conn
    conn |> cache(status, body) |> send_resp(status, body) |> halt()
  end

  def head(conn, status),
    do:
      conn
      |> frame("text/html")
      |> cache(status, "")
      |> send_resp(status, "")
      |> halt()

  defp frame(conn, type) do
    elapsed =
      System.convert_time_unit(
        System.monotonic_time() - conn.assigns.api_started,
        :native,
        :microsecond
      )

    conn
    |> RailsHeaders.call([])
    |> put_resp_header("content-type", type)
    |> put_resp_header("x-dawarich-response", conn.assigns.api_response)
    |> put_resp_header("x-dawarich-version", conn.assigns.api_version)
    |> put_resp_header("x-request-id", conn.assigns.api_request_id)
    |> put_resp_header("x-runtime", :erlang.float_to_binary(elapsed / 1_000_000, decimals: 6))
  end

  defp cache(conn, status, body) when status in [200, 201] and body != "" do
    digest = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower) |> binary_part(0, 32)

    conn
    |> put_resp_header("etag", ~s(W/"#{digest}"))
    |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")
  end

  defp cache(conn, _status, _body), do: put_resp_header(conn, "cache-control", "no-cache")
end
