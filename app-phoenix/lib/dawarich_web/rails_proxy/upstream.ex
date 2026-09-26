defmodule DawarichWeb.RailsProxy.Upstream do
  @moduledoc false

  @socket [:binary, active: false, packet: :raw, nodelay: true]

  def open({host, port}), do: :gen_tcp.connect(to_charlist(host), port, @socket, 30_000)

  def send_head(socket, method, target, headers) do
    :gen_tcp.send(socket, [
      method,
      " ",
      target,
      " HTTP/1.1\r\n",
      Enum.map(headers, fn {name, value} -> [name, ": ", value, "\r\n"] end),
      "\r\n"
    ])
  end

  def read_head(socket, buffer \\ "") do
    case :erlang.decode_packet(:http_bin, buffer, []) do
      {:ok, {:http_response, _version, status, _reason}, rest} ->
        read_headers(socket, rest, status, [])

      {:more, _} ->
        with {:ok, data} <- :gen_tcp.recv(socket, 0), do: read_head(socket, buffer <> data)

      _ ->
        {:error, :bad_response}
    end
  end

  def framing(headers) do
    headers = Enum.map(headers, fn {name, value} -> {String.downcase(name), value} end)

    case {List.keyfind(headers, "transfer-encoding", 0),
          List.keyfind(headers, "content-length", 0)} do
      {{_, _}, _} -> :chunked
      {nil, {_, length}} -> {:length, length |> String.trim() |> String.to_integer()}
      {nil, nil} -> :close
    end
  end

  def stream_body(socket, framing, buffer, acc, fun), do: body(framing, socket, buffer, acc, fun)

  defp read_headers(socket, buffer, status, acc) do
    case :erlang.decode_packet(:httph_bin, buffer, []) do
      {:ok, {:http_header, _, name, _, value}, rest} ->
        read_headers(socket, rest, status, [{field(name), value} | acc])

      {:ok, :http_eoh, rest} ->
        {:ok, status, Enum.reverse(acc), rest}

      {:more, _} ->
        with {:ok, data} <- :gen_tcp.recv(socket, 0),
             do: read_headers(socket, buffer <> data, status, acc)

      _ ->
        {:error, :bad_response}
    end
  end

  defp field(name) when is_atom(name), do: Atom.to_string(name)
  defp field(name), do: name

  defp body({:length, 0}, _socket, _buffer, acc, _fun), do: {:ok, acc}

  defp body({:chunk, 0}, socket, <<"\r\n", rest::binary>>, acc, fun),
    do: body(:chunked, socket, rest, acc, fun)

  defp body({:chunk, 0}, socket, buffer, acc, fun) when byte_size(buffer) < 2,
    do: more({:chunk, 0}, socket, buffer, acc, fun)

  defp body({:chunk, 0}, _socket, _buffer, acc, _fun), do: {:error, :bad_chunk, acc}
  defp body({kind, left}, socket, "", acc, fun), do: more({kind, left}, socket, "", acc, fun)

  defp body({kind, left}, socket, buffer, acc, fun) do
    size = min(left, byte_size(buffer))
    <<data::binary-size(size), rest::binary>> = buffer
    with {:ok, acc} <- fun.(data, acc), do: body({kind, left - size}, socket, rest, acc, fun)
  end

  defp body(:chunked, socket, buffer, acc, fun) do
    case :binary.split(buffer, "\r\n") do
      [line, rest] ->
        case Integer.parse(line, 16) do
          {0, _} -> {:ok, acc}
          {size, _} when size > 0 -> body({:chunk, size}, socket, rest, acc, fun)
          _ -> {:error, :bad_chunk, acc}
        end

      [_] ->
        more(:chunked, socket, buffer, acc, fun)
    end
  end

  defp body(:close, socket, buffer, acc, fun) do
    with {:ok, acc} <- fun.(buffer, acc) do
      case :gen_tcp.recv(socket, 0) do
        {:ok, data} -> body(:close, socket, data, acc, fun)
        {:error, :closed} -> {:ok, acc}
        {:error, reason} -> {:error, reason, acc}
      end
    end
  end

  defp more(state, socket, buffer, acc, fun) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} -> body(state, socket, buffer <> data, acc, fun)
      {:error, reason} -> {:error, reason, acc}
    end
  end
end
