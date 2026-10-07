defmodule DawarichWeb.A8FormDecode do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{RailsProxy, Api.Body}
  alias Plug.Conn.Query
  @max 2_097_152
  @pairs 4_096

  def params(conn, repeated_keys) do
    decoder = if conn.path_info == ["route_videos"], do: &DawarichWeb.RouteVideoRequest.decode/1

    case Body.kind(conn) do
      :form -> read(conn, [], &urlencoded(&1, repeated_keys, decoder))
      :none -> read(conn, [], fn "" -> %{} end)
      _ -> multipart(conn, repeated_keys, decoder)
    end
  end

  defp multipart(conn, repeated_keys, decoder) do
    with [type] <- get_req_header(conn, "content-type"),
         {:ok, "multipart", "form-data", %{"boundary" => boundary}} <-
           Plug.Conn.Utils.media_type(type),
         [length] <- get_req_header(conn, "content-length"),
         {size, ""} when size in 0..@max <- Integer.parse(length),
         false <- RailsProxy.Headers.chunked?(conn) do
      read(conn, [], &parts(&1, boundary, repeated_keys, decoder))
    else
      _ -> {:replay, conn}
    end
  end

  defp read(conn, acc, parse) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, data, conn} ->
        read(conn, [acc, data], parse)

      {:ok, data, conn} ->
        conn |> put_private(:dawarich_raw_body, IO.iodata_to_binary([acc, data])) |> decode(parse)

      {:error, _} ->
        {:error, conn}
    end
  end

  defp decode(conn, parse) do
    true = byte_size(conn.private.dawarich_raw_body) <= @max
    {:ok, conn, parse.(conn.private.dawarich_raw_body)}
  rescue
    _ -> {:replay, conn}
  end

  def urlencoded(raw, repeated_keys \\ [], decoder \\ nil) do
    true = length(:binary.matches(raw, "&")) < @pairs
    false = Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw)

    pairs =
      for pair <- String.split(raw, "&", trim: true) do
        [key, value] = String.split(pair, "=", parts: 2)
        {URI.decode_www_form(key), URI.decode_www_form(value)}
      end

    decode_pairs(pairs, repeated_keys, decoder)
  end

  defp parts(raw, boundary, repeated_keys, decoder) do
    ["" | rest] = String.split(raw, "--" <> boundary)
    {parts, [closing]} = Enum.split(rest, -1)
    true = closing in ["--", "--\r\n"] and length(parts) <= @pairs
    parts |> Enum.map(&part/1) |> decode_pairs(repeated_keys, decoder)
  end

  defp part("\r\n" <> part) do
    [head, value] = String.split(part, "\r\n\r\n", parts: 2)
    [_, name] = Regex.run(~r/\A(?i:content-disposition): form-data; name="([^"\r\n]*)"\z/, head)
    true = String.ends_with?(value, "\r\n")
    {name, String.replace_suffix(value, "\r\n", "")}
  end

  defp decode_pairs(pairs, repeated_keys, decoder) do
    true = Enum.all?(pairs, fn {key, value} -> String.valid?(key) and String.valid?(value) end)

    if decoder do
      arrays = for {key, _value} <- pairs, String.contains?(key, "[]"), do: key
      true = unique?(pairs, arrays)
      decoder.(pairs)
    else
      true = unique?(pairs, repeated_keys)

      pairs
      |> Enum.reduce(Query.decode_init(), fn {key, _value} = pair, acc ->
        true = Regex.match?(~r/\A[a-z_]+(?:\[[a-z_]*\]){0,3}\z/, key)
        Query.decode_each(pair, acc)
      end)
      |> Query.decode_done()
    end
  end

  defp unique?(pairs, repeated_keys) do
    Enum.reduce_while(pairs, MapSet.new(), fn {key, _}, seen ->
      duplicate = MapSet.member?(seen, key) and key not in repeated_keys

      conflict =
        Enum.any?(
          seen,
          &(String.starts_with?(key, &1 <> "[") or String.starts_with?(&1, key <> "["))
        )

      if duplicate or conflict, do: {:halt, false}, else: {:cont, MapSet.put(seen, key)}
    end) != false
  end
end
