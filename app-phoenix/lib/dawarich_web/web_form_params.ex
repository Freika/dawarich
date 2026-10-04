defmodule DawarichWeb.WebFormParams do
  @moduledoc false

  import Plug.Conn
  alias DawarichWeb.Api.Body
  alias DawarichWeb.RailsProxy
  alias Plug.Conn.Query

  @max 2_097_152
  @pairs 4_096

  def params(conn, opts \\ []) do
    if conn.query_string != "" and not Keyword.get(opts, :query, false) do
      {:replay, conn}
    else
      body(conn, Keyword.get(opts, :repeated, []))
    end
  end

  defp body(conn, repeated) do
    case Body.kind(conn) do
      :form -> read(conn, [], &urlencoded(&1, repeated))
      :none -> read(conn, [], fn "" -> %{} end)
      _ -> multipart(conn, repeated)
    end
  end

  defp multipart(conn, repeated) do
    with [type] <- get_req_header(conn, "content-type"),
         {:ok, "multipart", "form-data", %{"boundary" => boundary}} <-
           Plug.Conn.Utils.media_type(type),
         [length] <- get_req_header(conn, "content-length"),
         {size, ""} when size in 0..@max <- Integer.parse(length),
         false <- RailsProxy.Headers.chunked?(conn) do
      read(conn, [], &parts(&1, boundary, repeated))
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

  defp urlencoded(raw, repeated) do
    true = length(:binary.matches(raw, "&")) < @pairs
    false = Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw)

    pairs =
      for pair <- String.split(raw, "&", trim: true) do
        [key, value] = String.split(pair, "=", parts: 2)
        {URI.decode_www_form(key), URI.decode_www_form(value)}
      end

    decode_pairs(pairs, repeated)
  end

  defp parts(raw, boundary, repeated) do
    ["" | rest] = String.split(raw, "--" <> boundary)
    {parts, [closing]} = Enum.split(rest, -1)
    true = closing in ["--", "--\r\n"] and length(parts) <= @pairs
    parts |> Enum.map(&part/1) |> decode_pairs(repeated)
  end

  defp part("\r\n" <> part) do
    [head, value] = String.split(part, "\r\n\r\n", parts: 2)
    [_, name] = Regex.run(~r/\A(?i:content-disposition): form-data; name="([^"\r\n]*)"\z/, head)
    true = String.ends_with?(value, "\r\n")
    {name, String.replace_suffix(value, "\r\n", "")}
  end

  defp decode_pairs(pairs, repeated) do
    true = unique?(pairs, repeated)

    pairs
    |> Enum.reduce(Query.decode_init(), fn {key, value} = pair, acc ->
      true = String.valid?(key) and String.valid?(value)
      true = Regex.match?(~r/\A[a-z_]+(?:\[[a-z_]*\]){0,3}\z/, key)
      Query.decode_each(pair, acc)
    end)
    |> Query.decode_done()
  end

  defp unique?(pairs, repeated) do
    Enum.reduce_while(pairs, MapSet.new(), fn {key, _}, seen ->
      duplicate = MapSet.member?(seen, key) and key not in repeated

      conflict =
        Enum.any?(
          seen,
          &(String.starts_with?(key, &1 <> "[") or String.starts_with?(&1, key <> "["))
        )

      if duplicate or conflict, do: {:halt, false}, else: {:cont, MapSet.put(seen, key)}
    end) != false
  end
end
