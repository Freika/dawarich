defmodule DawarichWeb.Api.Transport do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.Api.SourceParams

  @json ~w(application/json text/x-json application/jsonrequest)
  @retained_multipart 2_097_152

  def init(opts), do: opts

  def call(conn, :router) do
    DawarichWeb.PageEnvelope.call(conn, :router)
  rescue
    exception in Plug.Conn.WrapperError ->
      if conn.private[:dawarich_native_api] do
        %{kind: kind, reason: reason, stack: stack} = exception
        Dawarich.ErrorReporting.capture_web(Exception.normalize(kind, reason, stack), stack)
        DawarichWeb.RailsErrors.respond(exception.conn, 500)
      else
        reraise(exception, __STACKTRACE__)
      end

    exception ->
      if conn.private[:dawarich_native_api] do
        Dawarich.ErrorReporting.capture_web(exception, __STACKTRACE__)
        DawarichWeb.RailsErrors.respond(conn, 500)
      else
        reraise(exception, __STACKTRACE__)
      end
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
      {:error, status, conn} -> error(conn, status)
    end
  rescue
    Plug.Parsers.RequestTooLargeError -> error(conn, 413)
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
        Plug.Parsers.init(parsers: [:multipart], pass: ["*/*"], length: limit(:multipart))

      parsed = DawarichWeb.Api.MultipartReplay.parse(conn, opts, @retained_multipart)
      {:ok, SourceParams.munge(parsed.body_params), parsed}
    else
      with {:ok, raw, conn} <- raw(conn, [], 0) do
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
  end

  defp limit(kind) do
    :dawarich |> Application.fetch_env!(:api_body_limits) |> Keyword.fetch!(kind)
  end

  defp json(""), do: {:ok, %{}}

  defp json(raw) do
    case Jason.decode(raw, objects: :ordered_objects) do
      {:ok, params} when is_map(params) -> {:ok, SourceParams.munge(params)}
      {:ok, params} -> {:ok, %{"_json" => SourceParams.munge(params)}}
      _ -> {:error, 400}
    end
  end

  defp raw(%{private: %{dawarich_raw_body: raw}} = conn, [], 0) do
    if byte_size(raw) > limit(:json), do: {:error, 413, conn}, else: {:ok, raw, conn}
  end

  defp raw(conn, acc, size) do
    case read_body(conn, length: 1_048_576, read_length: 1_048_576) do
      {status, data, conn} when status in [:ok, :more] ->
        size = size + byte_size(data)

        cond do
          size > limit(:json) -> {:error, 413, conn}
          status == :ok -> {:ok, IO.iodata_to_binary(Enum.reverse([data | acc])), conn}
          true -> raw(conn, [data | acc], size)
        end

      _ ->
        {:error, 400, conn}
    end
  end

  defp error(conn, status),
    do:
      conn
      |> DawarichWeb.RailsErrors.respond(status, transport: true)
end
