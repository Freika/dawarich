defmodule DawarichWeb.ActiveStorage.FileServer do
  @moduledoc false

  import Plug.Conn

  alias Dawarich.RubyInteger
  alias DawarichWeb.Api.Params

  @revalidate "max-age=0, private, must-revalidate"

  def byte_ranges([header], size) when size > 0 do
    with [_, spec] <- Regex.run(~r/bytes=([^;]+)/, header),
         true <- length(String.split(spec, ",")) <= 100,
         {:ok, ranges} <- specs(ruby_split(spec, ~r/,[ \t]*/), size, []) do
      if Enum.sum(Enum.map(ranges, fn {from, to} -> to - from + 1 end)) > size,
        do: [],
        else: ranges
    else
      _ -> nil
    end
  end

  def byte_ranges(_headers, _size), do: nil

  def serve(conn, path, size, modified) do
    if get_req_header(conn, "if-modified-since") == [modified] do
      conn |> delete_resp_header("content-type") |> no_cache() |> send_resp(304, "")
    else
      case byte_ranges(get_req_header(conn, "range"), size) do
        [] ->
          conn
          |> put_resp_header("content-range", "bytes */#{size}")
          |> no_cache()
          |> send_resp(416, "Byte range unsatisfiable\n")

        [{from, to}] ->
          conn
          |> put_resp_header("last-modified", modified)
          |> put_resp_header("content-range", "bytes #{from}-#{to}/#{size}")
          |> put_resp_header("cache-control", @revalidate)
          |> send_file(206, path, from, to - from + 1)

        _ ->
          conn
          |> put_resp_header("last-modified", modified)
          |> put_resp_header("cache-control", @revalidate)
          |> whole(path, modified)
      end
    end
  end

  def source(%{service: "local", root: root}, key, _opts) do
    with {:ok, path} <- Dawarich.Storage.safe_disk_path(root, key),
         {:ok, %{type: :regular}} <- File.stat(path) do
      {:ok, {:local, path}}
    else
      _ -> {:error, :missing}
    end
  end

  def source(%{service: "s3"} = config, key, _opts) do
    case s3(config, :head, key, %{}) do
      {:ok, %{headers: headers}} ->
        size = Enum.find_value(headers, fn {k,v} -> String.downcase(k) == "content-length" && String.to_integer(v) end)
        {:ok, {:s3, config, key, size}}
      {:error, {:http_error, 404, _}} -> {:error, :missing}
      _ -> {:error, :provider}
    end
  end

  def read_range!(%{service: "local", root: root}, key, first, last, _opts) do
    {:ok, path} = Dawarich.Storage.safe_disk_path(root, key)
    File.open!(path, [:read, :binary], fn io ->
      {:ok, bytes} = :file.pread(io, first, last-first+1)
      bytes
    end)
  end

  def read_range!(%{service: "s3"} = config, key, first, last, _opts) do
    {:ok, %{body: body}} = s3(config, :get, key, %{"range" => "bytes=#{first}-#{last}"})
    body
  end

  def stream(%{method: "HEAD"} = conn, _source, _opts), do: send_resp(conn, 200, "")
  def stream(conn, {:local, path}, opts) do
    conn = send_chunked(conn, 200)
    Enum.reduce_while(File.stream!(path, 65_536), conn, fn bytes, conn -> send_chunk(conn, bytes, opts) end)
  end

  def stream(conn, {:s3, config, key, size}, opts) do
    conn = send_chunked(conn, 200)
    if size == 0 do
      conn
    else
      Enum.reduce_while(0..div(size-1, 65_536), conn, fn part, conn ->
        bytes = read_range!(config, key, part*65_536, min((part+1)*65_536-1,size-1), opts)
        send_chunk(conn, bytes, opts)
      end)
    end
  end

  defp send_chunk(conn, bytes, opts) do
    case chunk(conn, bytes) do
      {:ok, conn} ->
        if callback = opts[:after_chunk], do: callback.(conn)
        {:cont, conn}
      {:error, _} -> {:halt, halt(conn)}
    end
  end

  defp s3(config, method, key, headers) do
    %ExAws.Operation.S3{http_method: method, bucket: config.bucket, path: key, headers: headers, parser: & &1}
    |> ExAws.request(config.ex_aws)
  end

  defp specs([], _size, acc), do: {:ok, Enum.reverse(acc)}

  defp specs([spec | rest], size, acc) do
    case String.contains?(spec, "-") && range(ruby_split(spec, "-"), size) do
      false -> :error
      :error -> :error
      nil -> specs(rest, size, acc)
      range -> specs(rest, size, [range | acc])
    end
  end

  defp ruby_split(string, pattern),
    do:
      string
      |> String.split(pattern)
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 == ""))
      |> Enum.reverse()

  defp range([first | rest], size) when first != "" do
    from = RubyInteger.to_i(first)

    case rest do
      [] ->
        keep(from, size - 1)

      [last | _] ->
        if RubyInteger.to_i(last) < from,
          do: :error,
          else: keep(from, min(RubyInteger.to_i(last), size - 1))
    end
  end

  defp range([_empty, last | _], size), do: keep(max(size - RubyInteger.to_i(last), 0), size - 1)
  defp range(_parts, _size), do: :error

  defp keep(from, to) when from <= to, do: {from, to}
  defp keep(_from, _to), do: nil

  defp whole(conn, path, modified) do
    if fresh?(conn, modified),
      do: conn |> delete_resp_header("content-type") |> send_resp(304, ""),
      else: send_file(conn, 200, path)
  end

  defp fresh?(conn, modified) do
    with [] <- get_req_header(conn, "if-none-match"),
         {:ok, %NaiveDateTime{} = since} <- Params.if_modified_since(conn),
         {:ok, last} <-
           Params.if_modified_since(%Plug.Conn{req_headers: [{"if-modified-since", modified}]}) do
      NaiveDateTime.compare(since, last) != :lt
    else
      _ -> false
    end
  end

  defp no_cache(conn), do: put_resp_header(conn, "cache-control", "no-cache")
end
