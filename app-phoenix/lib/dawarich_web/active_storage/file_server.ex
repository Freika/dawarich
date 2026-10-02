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
