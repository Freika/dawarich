defmodule DawarichWeb.Api.Respond do
  @moduledoc false

  import Plug.Conn

  require Logger

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.RailsHeaders

  def json(conn, status, term) do
    body = term |> Ruby.json() |> IO.iodata_to_binary()
    conn = frame(conn, "application/json; charset=utf-8")
    conn = if conn.assigns.api_vary, do: put_resp_header(conn, "vary", "Accept"), else: conn
    log(conn, status)
    conn |> cache(status, body) |> finish(status, body)
  end

  defp finish(%{method: "GET"} = conn, 200, body) do
    if get_resp_header(conn, "etag") == [conn.assigns.api_if_none_match],
      do: conn |> delete_resp_header("content-type") |> send_resp(304, "") |> halt(),
      else: conn |> send_resp(200, body) |> halt()
  end

  defp finish(conn, status, body), do: conn |> send_resp(status, body) |> halt()

  def head(conn, status) do
    conn = frame(conn, "text/html")
    log(conn, status)
    conn |> cache(status, "") |> send_resp(status, "") |> halt()
  end

  defp log(conn, status) do
    Logger.info(
      "[ingest] #{conn.method} #{conn.request_path} #{status} #{elapsed_ms(conn)}ms request_id=#{conn.assigns.api_request_id}"
    )
  end

  defp elapsed_ms(conn),
    do:
      System.convert_time_unit(
        System.monotonic_time() - conn.assigns.api_started,
        :native,
        :millisecond
      )

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
    |> merge_resp_headers(conn.assigns.api_headers)
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
