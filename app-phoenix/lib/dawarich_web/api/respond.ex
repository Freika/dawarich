defmodule DawarichWeb.Api.Respond do
  @moduledoc false

  import Plug.Conn

  require Logger

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.RailsHeaders

  def json(conn, status, term, opts \\ []),
    do:
      send_body(
        conn,
        status,
        term |> Ruby.json() |> IO.iodata_to_binary(),
        "application/json; charset=utf-8",
        opts
      )

  def data(conn, body, type, opts) do
    conn
    |> put_resp_header("content-disposition", "inline")
    |> put_resp_header("content-transfer-encoding", "binary")
    |> send_body(200, body, type, opts)
  end

  defp send_body(conn, status, body, type, opts) do
    conn = frame(conn, type)
    conn = if conn.assigns.api_vary, do: put_resp_header(conn, "vary", "Accept"), else: conn
    conn = cache(conn, status, body, opts)
    final = final_status(conn, status)
    log(conn, final)
    finish(final, conn, body)
  end

  defp final_status(%{method: "GET"} = conn, 200) do
    if get_resp_header(conn, "etag") == [conn.assigns.api_if_none_match], do: 304, else: 200
  end

  defp final_status(_conn, status), do: status

  defp finish(304, conn, _body),
    do: conn |> delete_resp_header("content-type") |> send_resp(304, "") |> halt()

  defp finish(status, conn, body), do: conn |> send_resp(status, body) |> halt()

  def head(conn, status) do
    conn = frame(conn, "text/html")
    log(conn, status)
    conn |> cache(status, "", []) |> send_resp(status, "") |> halt()
  end

  def not_modified(conn, last_modified) do
    conn = frame(conn, "")
    log(conn, 304)

    conn
    |> delete_resp_header("content-type")
    |> put_resp_header("last-modified", last_modified)
    |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")
    |> send_resp(304, "")
    |> halt()
  end

  defp log(conn, status) do
    Logger.info(
      "[#{conn.assigns.api_tag}] #{conn.method} #{conn.request_path} #{status} #{elapsed_ms(conn)}ms request_id=#{conn.assigns.api_request_id}"
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

  defp cache(conn, status, body, opts) when status in [200, 201] and body != "" do
    case Keyword.fetch(opts, :last_modified) do
      {:ok, stamp} ->
        conn
        |> put_resp_header("last-modified", stamp)
        |> put_resp_header("cache-control", Keyword.fetch!(opts, :cache_control))

      :error ->
        rack_etag(
          conn,
          body,
          Keyword.get(opts, :cache_control, "max-age=0, private, must-revalidate")
        )
    end
  end

  defp cache(conn, _status, _body, _opts), do: put_resp_header(conn, "cache-control", "no-cache")

  def rack_etag(conn, body, cache_control \\ "max-age=0, private, must-revalidate") do
    digest = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower) |> binary_part(0, 32)

    conn
    |> put_resp_header("etag", ~s(W/"#{digest}"))
    |> put_resp_header("cache-control", cache_control)
  end
end
