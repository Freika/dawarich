defmodule DawarichWeb.Api.Transport do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.Api.SourceParams

  @json ~w(application/json text/x-json application/jsonrequest)

  def init(opts), do: opts

  def call(conn, :router) do
    DawarichWeb.Router.call(conn, DawarichWeb.Router.init([]))
  rescue
    exception in Plug.Conn.WrapperError ->
      if conn.private[:dawarich_native_api],
        do: DawarichWeb.RailsErrors.respond(exception.conn, 500),
        else: reraise(exception, __STACKTRACE__)

    exception ->
      if conn.private[:dawarich_native_api],
        do: DawarichWeb.RailsErrors.respond(conn, 500),
        else: reraise(exception, __STACKTRACE__)
  end

  def parse(%{private: %{dawarich_body_parsed: true}} = conn), do: conn

  def parse(conn) do
    with {:ok, query} <- SourceParams.decode(conn.query_string),
         {:ok, body, conn} <- body(conn) do
      conn
      |> put_private(:dawarich_body_parsed, true)
      |> assign(:api_query, query)
      |> assign(:api_params, Map.merge(body, query))
    else
      {:error, status} -> error(conn, status)
    end
  rescue
    _ -> error(conn, 400)
  end

  def media_type(conn) do
    conn
    |> get_req_header("content-type")
    |> List.first("")
    |> String.split(";")
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp body(conn) do
    type = media_type(conn)

    if type == "multipart/form-data" do
      opts =
        Plug.Parsers.init(parsers: [:multipart], pass: ["*/*"], length: 9_223_372_036_854_775_807)

      parsed = DawarichWeb.Api.MultipartReplay.parse(conn, opts)
      {:ok, SourceParams.munge(parsed.body_params), parsed}
    else
      {raw, conn} = raw(conn, [])
      conn = put_private(conn, :dawarich_raw_body, raw)

      result =
        cond do
          type in @json -> json(raw)
          type == "application/x-www-form-urlencoded" -> SourceParams.decode(raw)
          true -> {:ok, %{}}
        end

      case result do
        {:ok, params} -> {:ok, params, conn}
        error -> error
      end
    end
  end

  defp json(""), do: {:ok, %{}}

  defp json(raw) do
    case Jason.decode(raw, objects: :ordered_objects) do
      {:ok, params} when is_map(params) -> {:ok, SourceParams.munge(params)}
      {:ok, params} -> {:ok, %{"_json" => SourceParams.munge(params)}}
      _ -> {:error, 400}
    end
  end

  defp raw(%{private: %{dawarich_raw_body: raw}} = conn, []), do: {raw, conn}

  defp raw(conn, acc) do
    case read_body(conn, length: 1_048_576, read_length: 1_048_576) do
      {:ok, data, conn} -> {IO.iodata_to_binary(Enum.reverse([data | acc])), conn}
      {:more, data, conn} -> raw(conn, [data | acc])
      _ -> throw(:bad_body)
    end
  end

  defp error(conn, status),
    do:
      conn
      |> DawarichWeb.RailsErrors.respond(status, transport: true)
end
