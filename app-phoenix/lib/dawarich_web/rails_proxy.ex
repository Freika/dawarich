defmodule DawarichWeb.RailsProxy do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias DawarichWeb.RailsProxy.{Headers, Upstream}

  defmodule UpstreamClosed do
    defexception [:reason]

    @impl true
    def message(%{reason: reason}),
      do: "Puma closed the proxied response early: #{inspect(reason)}"
  end

  @read [length: 1_048_576, read_length: 1_048_576, read_timeout: 60_000]

  def read_options, do: @read

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :upstream)

  @impl true
  def call(conn, upstream) do
    conn = DawarichWeb.RateLimit.release(conn)

    if Headers.websocket_upgrade?(conn),
      do: DawarichWeb.CableProxy.upgrade(conn, upstream),
      else: with_upstream(conn, upstream, &forward/2)
  end

  @doc false
  def with_upstream(conn, upstream, fun) do
    case Upstream.open(upstream) do
      {:ok, socket} -> fun.(conn, socket)
      {:error, reason} -> bad_gateway(conn, reason)
    end
  end

  @doc false
  def bad_gateway(conn, reason) do
    Logger.warning("Puma did not answer the proxied request: #{inspect(reason)}")
    conn |> put_resp_content_type("text/plain") |> send_resp(502, "Bad Gateway") |> halt()
  end

  @doc false
  def respond(conn, socket, status, headers, rest) do
    conn = %{conn | resp_headers: Headers.response(headers)}

    if Headers.bodyless?(conn.method, status) do
      close(socket, conn |> send_resp(status, "") |> halt())
    else
      stream_response(send_chunked(conn, status), socket, Upstream.framing(headers), rest)
    end
  end

  defp forward(conn, socket) do
    with :ok <-
           Upstream.send_head(socket, conn.method, Headers.target(conn), Headers.request(conn)),
         {:ok, conn} <- send_body(conn, socket),
         {:ok, status, headers, rest} <- final_head(socket, "") do
      respond(conn, socket, status, headers, rest)
    else
      {:client_gone, conn} -> close(socket, halt(conn))
      {:error, reason} -> close(socket, bad_gateway(conn, reason))
    end
  end

  defp send_body(conn, socket) do
    cond do
      Map.has_key?(conn.private, :dawarich_raw_body) ->
        with :ok <- :gen_tcp.send(socket, conn.private.dawarich_raw_body), do: {:ok, conn}

      Headers.chunked?(conn) ->
        relay_body(conn, socket, &chunk_frame/1, "0\r\n\r\n")

      Headers.body?(conn) ->
        relay_body(conn, socket, & &1, [])

      true ->
        {:ok, conn}
    end
  end

  defp relay_body(conn, socket, frame, last) do
    case read_body(conn, @read) do
      {:more, data, conn} ->
        with :ok <- :gen_tcp.send(socket, frame.(data)), do: relay_body(conn, socket, frame, last)

      {:ok, data, conn} ->
        with :ok <- :gen_tcp.send(socket, [frame.(data), last]), do: {:ok, conn}

      {:error, _reason} ->
        {:client_gone, conn}
    end
  end

  defp chunk_frame(""), do: []
  defp chunk_frame(data), do: [Integer.to_string(byte_size(data), 16), "\r\n", data, "\r\n"]

  defp final_head(socket, buffer) do
    case Upstream.read_head(socket, buffer) do
      {:ok, status, _headers, rest} when status in 100..199 -> final_head(socket, rest)
      result -> result
    end
  end

  defp stream_response(conn, socket, framing, rest) do
    result = Upstream.stream_body(socket, framing, rest, conn, &to_client/2)
    :gen_tcp.close(socket)

    case result do
      {:ok, conn} -> halt(conn)
      {:client_gone, conn} -> halt(conn)
      {:error, reason, _conn} -> raise UpstreamClosed, reason: reason
    end
  end

  defp to_client("", conn), do: {:ok, conn}

  defp to_client(data, conn) do
    case chunk(conn, data) do
      {:ok, conn} -> {:ok, conn}
      {:error, _reason} -> {:client_gone, conn}
    end
  end

  defp close(socket, conn) do
    :gen_tcp.close(socket)
    conn
  end
end
