defmodule DawarichWeb.ImportsRequest do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.Api.Body
  alias DawarichWeb.{RailsForm, RailsProxy}
  alias Plug.Conn.Query

  @rack_params 4_096
  @max 2_097_152

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case params(conn) do
      {:ok, conn} -> admit(conn)
      {:replay, conn, reason} -> Body.replay(conn, reason)
      {:halt, conn} -> halt(conn)
    end
  end

  defp admit(conn) do
    with :ok <- page(conn), :ok <- RailsForm.admission(conn) do
      conn = DawarichWeb.ImportsAuthorization.call(conn)

      if conn.halted,
        do: conn,
        else: put_resp_header(conn, "x-dawarich-handler", "phoenix-imports")
    else
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  defp params(%{query_string: query} = conn) when query != "",
    do: {:replay, conn, "query string"}

  defp params(conn) do
    case Body.kind(conn) do
      :none -> {:ok, assign_params(conn, %{})}
      :form -> read(conn, [], &urlencoded/1)
      _ -> multipart(conn)
    end
  end

  defp multipart(conn) do
    with [type] <- get_req_header(conn, "content-type"),
         {:ok, "multipart", "form-data", %{"boundary" => boundary}} <-
           Plug.Conn.Utils.media_type(type),
         [length] <- get_req_header(conn, "content-length"),
         {size, ""} when size <= @max <- Integer.parse(length),
         false <- RailsProxy.Headers.chunked?(conn) do
      read(conn, [], &parts(&1, boundary))
    else
      _ -> {:replay, conn, "request body"}
    end
  end

  defp read(conn, acc, parse) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, data, conn} ->
        read(conn, [acc, data], parse)

      {:ok, data, conn} ->
        conn
        |> put_private(:dawarich_raw_body, IO.iodata_to_binary([acc, data]))
        |> decode(parse)

      {:error, _reason} ->
        {:halt, conn}
    end
  end

  defp decode(conn, parse) do
    body = parse.(conn.private.dawarich_raw_body)

    module = request_module(conn)

    if Enum.all?(body, &module.field?/1),
      do: {:ok, assign_params(conn, body)},
      else: {:replay, conn, "parameter shape"}
  rescue
    _error -> {:replay, conn, "parameter shape"}
  end

  defp urlencoded(raw) do
    true = length(:binary.matches(raw, "&")) < @rack_params - 1
    Query.decode(raw)
  end

  defp parts(raw, boundary) do
    [_preamble | rest] = String.split(raw, "--" <> boundary)
    {parts, [closing]} = Enum.split(rest, -1)
    true = closing in ["--", "--\r\n"] and length(parts) < @rack_params

    parts
    |> Enum.map(&part/1)
    |> Enum.reduce(Query.decode_init(), &Query.decode_each/2)
    |> Query.decode_done()
  end

  defp part("\r\n" <> part) do
    [head, value] = String.split(part, "\r\n\r\n", parts: 2)
    [_, name] = Regex.run(~r/\A(?i:content-disposition): form-data; name="([^"\r\n]*)"\z/, head)
    true = String.ends_with?(value, "\r\n")
    {name, String.replace_suffix(value, "\r\n", "")}
  end

  def request_module(%{path_info: ["imports"], method: "POST"}),
    do: DawarichWeb.Imports.UploadForm

  def request_module(_), do: DawarichWeb.Imports.UpdateForm

  defp assign_params(conn, body) do
    %{conn | body_params: body, params: Map.merge(body, conn.path_params)}
    |> assign(:api_query, %{})
    |> assign(:api_params, Map.delete(body, "_method"))
  end

  defp page(conn) do
    if Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "turbo-stream")) do
      formats =
        DawarichWeb.PageAccept.formats(Enum.join(get_req_header(conn, "accept"), ", "), false)

      if match?(["imports", _, "extraction"], conn.path_info) and is_list(formats) and
           DawarichWeb.PageAccept.negotiate(formats, ~w(text/vnd.turbo-stream.html text/html)),
         do: :ok,
         else: {:replay, "turbo stream"}
    else
      :ok
    end
  end
end
