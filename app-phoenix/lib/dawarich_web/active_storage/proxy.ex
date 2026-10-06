defmodule DawarichWeb.ActiveStorage.Proxy do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{RailsMessages, Storage}
  alias Dawarich.Storage.Blobs
  alias DawarichWeb.ActiveStorageUrls
  alias DawarichWeb.ActiveStorage.FileServer

  def call(conn, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.services!(System.get_env()) end)
    conn = fetch_query_params(conn)

    with {:ok, id} <- RailsMessages.verified_blob_id(conn.path_params["signed_id"], now),
         blob when not is_nil(blob) <- Blobs.find(id) do
      serve(conn, blob, Storage.service!(storage, blob.service_name), opts)
    else
      :error -> empty(conn, 404)
      nil -> page(conn, 404)
    end
  end

  def serve(conn, blob, service, opts \\ []) do
    conn = fetch_query_params(conn)
    ranges = get_req_header(conn, "range")

    if ranges != [] and not Keyword.get(opts, :representation, false) do
      range(conn, blob, service, ranges, opts)
    else
      whole(conn, blob, service, opts)
    end
  end

  defp whole(conn, blob, service, opts) do
    conn = cached(conn)

    if fresh?(conn) do
      conn |> delete_resp_header("content-type") |> send_resp(304, "")
    else
      conn =
        conn
        |> headers(blob, conn.query_params["disposition"])
        |> put_resp_header("content-length", to_string(blob.byte_size))

      conn =
        if Keyword.get(opts, :representation, false),
          do: conn,
          else: put_resp_header(conn, "accept-ranges", "bytes")

      case FileServer.source(service, blob.key, opts) do
        {:ok, source} -> FileServer.stream(conn, source, opts)
        {:error, :missing} -> failed_stream(conn, 404)
        {:error, _} -> failed_stream(conn, 500)
      end
    end
  end

  defp range(conn, blob, service, headers, opts) do
    ranges = FileServer.byte_ranges(headers, blob.byte_size)

    if is_list(ranges) and ranges != [] and length(ranges) <= 100 and
         Enum.sum(Enum.map(ranges, fn {a, b} -> b - a end)) < 5_242_880 do
      try do
        {body, type, range} = range_body(ranges, blob, service, opts)

        conn =
          conn
          |> headers(blob, nil)
          |> put_resp_header("content-type", type)
          |> put_resp_header("accept-ranges", "bytes")
          |> put_resp_header("content-length", to_string(byte_size(body)))
          |> put_resp_header("cache-control", "no-cache")

        conn = if range, do: put_resp_header(conn, "content-range", range), else: conn
        send_resp(conn, 206, if(conn.method == "HEAD", do: "", else: body))
      rescue
        _ -> empty(conn, 500)
      end
    else
      empty(conn, 416)
    end
  end

  defp range_body([{first, last}], blob, service, opts) do
    {FileServer.read_range!(service, blob.key, first, last, opts), content_type(blob),
     "bytes #{first}-#{last}/#{blob.byte_size}"}
  end

  defp range_body(ranges, blob, service, opts) do
    boundary =
      Keyword.get_lazy(opts, :boundary, fn ->
        Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
      end)

    body =
      Enum.map_join(ranges, fn {first, last} ->
        "\r\n--#{boundary}\r\nContent-Type: #{content_type(blob)}\r\nContent-Range: bytes #{first}-#{last}/#{blob.byte_size}\r\n\r\n" <>
          FileServer.read_range!(service, blob.key, first, last, opts)
      end)

    {body <> "\r\n--#{boundary}--\r\n", "multipart/byteranges; boundary=#{boundary}", nil}
  end

  defp headers(conn, blob, disposition) do
    forced =
      blob.content_type in ActiveStorageUrls.binary_types() or
        blob.content_type not in ActiveStorageUrls.inline_types()

    type = if forced, do: "attachment", else: disposition || "inline"

    conn
    |> put_resp_header("content-type", content_type(blob))
    |> put_resp_header("content-disposition", Storage.content_disposition(type, blob.filename))
  end

  defp content_type(blob),
    do:
      if(blob.content_type in ActiveStorageUrls.binary_types(),
        do: "application/octet-stream",
        else: blob.content_type || "application/octet-stream"
      )

  def cached(conn) do
    path =
      conn.request_path <> if(conn.query_string == "", do: "", else: "?" <> conn.query_string)

    digest = :crypto.hash(:sha256, path) |> Base.encode16(case: :lower) |> binary_part(0, 32)

    conn
    |> put_resp_header("etag", ~s(W/"#{digest}"))
    |> put_resp_header("last-modified", DawarichWeb.Api.Params.http_date(modified()))
    |> put_resp_header("cache-control", "max-age=3155695200, public, immutable")
  end

  defp modified do
    {{2011, 1, 1}, {0, 0, 0}}
    |> :calendar.local_time_to_universal_time_dst()
    |> hd()
    |> NaiveDateTime.from_erl!()
  end

  defp fresh?(conn) do
    etags =
      get_req_header(conn, "if-none-match")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)

    if etags != [],
      do: "*" in etags or hd(get_resp_header(conn, "etag")) in etags,
      else:
        (case DawarichWeb.Api.Params.if_modified_since(conn) do
           {:ok, %NaiveDateTime{} = since} ->
             NaiveDateTime.compare(since, modified()) != :lt

           _ ->
             false
         end)
  end

  def failed_stream(conn, status) do
    conn
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("content-length", "0")
    |> send_resp(status, "")
  end

  def empty(conn, status) do
    conn
    |> delete_resp_header("etag")
    |> delete_resp_header("last-modified")
    |> delete_resp_header("content-disposition")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header(
      "content-type",
      if(
        status == 416 and
          Path.extname(to_string(List.last(List.wrap(conn.path_params["filename"])))) == ".json",
        do: "application/json",
        else: "text/html"
      )
    )
    |> put_resp_header("content-length", "0")
    |> send_resp(status, "")
  end

  def page(conn, status) do
    body = File.read!(Dawarich.RailsRoot.join("public/#{status}.html"))

    conn
    |> delete_resp_header("cache-control")
    |> put_resp_header("content-type", "text/html; charset=UTF-8")
    |> put_resp_header("content-length", to_string(byte_size(body)))
    |> send_resp(status, body)
  end
end
