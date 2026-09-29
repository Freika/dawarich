defmodule DawarichWeb.Api.Body do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias DawarichWeb.RailsProxy

  @max 2_097_152
  @json ~w(application/json text/x-json application/jsonrequest)
  @form "application/x-www-form-urlencoded"
  @pairs 4_096
  @depth 32

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case classify(conn) do
      {:proxy, reason} -> replay(conn, reason)
      {kind, nil} -> decode(conn, kind)
    end
  end

  def replay(conn, reason) do
    Logger.info("[ingest] #{conn.request_path} handed to Rails: #{reason}")

    conn |> RailsProxy.call(upstream()) |> halt()
  end

  @doc false
  def kind(conn), do: conn |> classify() |> elem(0)

  defp classify(conn) do
    length = conn |> get_req_header("content-length") |> List.first()

    type =
      conn
      |> get_req_header("content-type")
      |> List.first("")
      |> String.split(";")
      |> hd()
      |> String.trim()
      |> String.downcase()

    cond do
      RailsProxy.Headers.chunked?(conn) ->
        {:proxy, "chunked request body"}

      length in [nil, "0"] ->
        {:none, nil}

      not (length =~ ~r/\A\d+\z/) or String.to_integer(length) > @max ->
        {:proxy, "body larger than 2 MiB"}

      type in @json ->
        {:json, nil}

      type == @form ->
        {:form, nil}

      true ->
        {:proxy, "content type #{type}"}
    end
  end

  defp decode(conn, kind) do
    case read(conn, []) do
      {:ok, raw, conn} ->
        conn = put_private(conn, :dawarich_raw_body, raw)

        with {:ok, body} <- body(kind, raw), {:ok, query} <- pairs(conn.query_string) do
          assign(conn, :api_params, Map.merge(body, query))
        else
          {:replay, reason} -> replay(conn, reason)
        end

      {:error, conn} ->
        halt(conn)
    end
  end

  defp read(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:ok, data, conn} -> {:ok, IO.iodata_to_binary([acc, data]), conn}
      {:more, data, conn} -> read(conn, [acc, data])
      {:error, _reason} -> {:error, conn}
    end
  end

  defp body(:none, _raw), do: {:ok, %{}}
  defp body(:form, raw), do: pairs(raw)
  defp body(:json, ""), do: {:ok, %{}}

  defp body(:json, raw) do
    case Jason.decode(raw) do
      {:ok, term} ->
        if too_deep?(term, 0),
          do: {:replay, "JSON nested deeper than #{@depth}"},
          else: {:ok, wrap(munge(term))}

      {:error, _} ->
        {:replay, "JSON Jason does not read"}
    end
  end

  defp wrap(map) when is_map(map), do: map
  defp wrap(other), do: %{"_json" => other}

  defp munge(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, munge(v)} end)
  defp munge(list) when is_list(list), do: for(e <- list, e != nil, do: munge(e))
  defp munge(value), do: value

  defp too_deep?(map, depth) when is_map(map),
    do: depth >= @depth or Enum.any?(map, fn {_key, value} -> too_deep?(value, depth + 1) end)

  defp too_deep?(list, depth) when is_list(list),
    do: depth >= @depth or Enum.any?(list, &too_deep?(&1, depth + 1))

  defp too_deep?(_term, _depth), do: false

  defp pairs(""), do: {:ok, %{}}

  defp pairs(text) do
    if more_pairs?(text) or byte_size(text) > 4_194_304,
      do: {:replay, "more parameters than Rack allows"},
      else:
        text
        |> String.split(~r/& */)
        |> Enum.reject(&(&1 == ""))
        |> Enum.reduce_while({:ok, %{}}, &pair/2)
  end

  defp more_pairs?(text), do: more_pairs?(text, 0)
  defp more_pairs?(<<"&", _rest::binary>>, count) when count + 1 >= @pairs, do: true
  defp more_pairs?(<<"&", rest::binary>>, count), do: more_pairs?(rest, count + 1)
  defp more_pairs?(<<_byte, rest::binary>>, count), do: more_pairs?(rest, count)
  defp more_pairs?("", _count), do: false

  defp pair(segment, {:ok, acc}) do
    with [key, value] <- String.split(segment, "=", parts: 2),
         {:ok, key} when key != "" <- component(key),
         false <- String.contains?(key, ["[", "]"]),
         {:ok, value} <- component(value) do
      {:cont, {:ok, Map.put(acc, key, value)}}
    else
      _ -> {:halt, {:replay, "form or query shape Rack parses differently"}}
    end
  end

  defp component(part) do
    decoded = URI.decode_www_form(part)
    if String.valid?(decoded), do: {:ok, decoded}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp upstream, do: Application.fetch_env!(:dawarich, :rails_upstream)
end
