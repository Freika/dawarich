defmodule DawarichWeb.CableProxy do
  @moduledoc false
  @behaviour WebSock

  import Plug.Conn

  alias DawarichWeb.CableProxy.Frame
  alias DawarichWeb.RailsProxy
  alias DawarichWeb.RailsProxy.{Headers, Upstream}

  def upgrade_options, do: [timeout: :infinity, compress: false]

  def upgrade(conn, upstream) do
    case WebSockAdapter.UpgradeValidation.validate_upgrade(conn) do
      :ok ->
        RailsProxy.with_upstream(conn, upstream, &handshake/2)

      {:error, _reason} ->
        bad_request(conn)
    end
  end

  def bad_request(conn),
    do: conn |> put_resp_content_type("text/plain") |> send_resp(400, "Bad Request") |> halt()

  defp handshake(conn, socket) do
    with :ok <- Upstream.send_head(socket, "GET", Headers.target(conn), upgrade_headers(conn)),
         {:ok, 101, headers, rest} <- Upstream.read_head(socket) do
      %{conn | resp_headers: subprotocol(headers)}
      |> WebSockAdapter.upgrade(
        __MODULE__,
        %{socket: socket, buffer: rest, fragments: nil},
        upgrade_options()
      )
      |> halt()
    else
      {:ok, status, headers, rest} ->
        RailsProxy.respond(conn, socket, status, headers, rest)

      {:error, reason} ->
        :gen_tcp.close(socket)
        RailsProxy.bad_gateway(conn, reason)
    end
  end

  defp upgrade_headers(conn) do
    Enum.reject(Headers.request(conn), fn {name, _} ->
      name in ["connection", "sec-websocket-extensions"]
    end) ++
      [{"connection", "Upgrade"}, {"upgrade", "websocket"}]
  end

  defp subprotocol(headers) do
    for {name, value} <- headers,
        String.downcase(name) == "sec-websocket-protocol",
        do: {"sec-websocket-protocol", value}
  end

  @impl WebSock
  def init(state) do
    _ = :inet.setopts(state.socket, active: :once)
    from_puma(state, state.buffer)
  end

  @impl WebSock
  def handle_in({data, opcode: opcode}, state), do: to_puma(state, opcode, data)

  @impl WebSock
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    _ = :inet.setopts(socket, active: :once)
    from_puma(state, state.buffer <> data)
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state),
    do: {:stop, :normal, 1011, state}

  def handle_info({:tcp_error, socket, _reason}, %{socket: socket} = state),
    do: {:stop, :normal, 1011, state}

  def handle_info(_message, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, state) do
    _ = :gen_tcp.send(state.socket, Frame.encode(:close, <<1000::16>>))
    :gen_tcp.close(state.socket)
  end

  defp from_puma(state, buffer) do
    case Frame.decode(buffer) do
      {:ok, frames, rest} -> relay(frames, %{state | buffer: rest}, [])
      :error -> {:stop, :normal, 1002, state}
    end
  end

  defp relay([], state, []), do: {:ok, state}
  defp relay([], state, out), do: {:push, Enum.reverse(out), state}

  defp relay([{true, kind, payload} | rest], %{fragments: nil} = state, out)
       when kind in [:text, :binary],
       do: relay(rest, state, [{kind, payload} | out])

  defp relay([{false, kind, payload} | rest], %{fragments: nil} = state, out)
       when kind in [:text, :binary],
       do: relay(rest, %{state | fragments: {kind, [payload]}}, out)

  defp relay([{fin, :continuation, payload} | rest], %{fragments: {kind, parts}} = state, out) do
    if fin,
      do:
        relay(rest, %{state | fragments: nil}, [
          {kind, IO.iodata_to_binary([parts, payload])} | out
        ]),
      else: relay(rest, %{state | fragments: {kind, [parts, payload]}}, out)
  end

  defp relay([{true, :ping, payload} | rest], state, out) do
    case :gen_tcp.send(state.socket, Frame.encode(:pong, payload)) do
      :ok -> relay(rest, state, out)
      {:error, _} -> {:stop, :normal, 1011, Enum.reverse(out), state}
    end
  end

  defp relay([{true, :pong, _} | rest], state, out), do: relay(rest, state, out)

  defp relay([{true, :close, <<code::16, reason::binary>>} | _], state, out),
    do: {:stop, :normal, {code, reason}, Enum.reverse(out), state}

  defp relay([{true, :close, _} | _], state, out),
    do: {:stop, :normal, 1000, Enum.reverse(out), state}

  defp relay(_frames, state, out), do: {:stop, :normal, 1002, Enum.reverse(out), state}

  defp to_puma(state, kind, data) do
    case :gen_tcp.send(state.socket, Frame.encode(kind, data)) do
      :ok -> {:ok, state}
      {:error, _} -> {:stop, :normal, 1011, state}
    end
  end
end
