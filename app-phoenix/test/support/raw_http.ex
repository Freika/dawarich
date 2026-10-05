defmodule Dawarich.Test.RawHTTP do
  @moduledoc false

  def listen(options \\ []) do
    {:ok, listen} =
      :gen_tcp.listen(
        0,
        [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true] ++ options
      )

    {:ok, port} = :inet.port(listen)
    %{listen: listen, port: port}
  end

  def accept(%{listen: listen}) do
    {:ok, socket} = :gen_tcp.accept(listen, 5_000)
    socket
  end

  def accept_on_request(%{listen: listen}, request) do
    owner = self()

    task =
      Task.async(fn ->
        send(owner, {self(), :accepting})
        {:ok, socket} = :gen_tcp.accept(listen)
        :ok = :gen_tcp.controlling_process(socket, owner)
        socket
      end)

    receive do: ({pid, :accepting} when pid == task.pid -> :ok)
    result = request.()
    {Task.await(task, :infinity), result}
  end

  def connect(port, timeout \\ 5_000) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], timeout)
    socket
  end

  def send_raw(socket, data), do: :ok = :gen_tcp.send(socket, data)
  def reply(socket, data), do: send_raw(socket, data)

  def read_head(socket, acc \\ "") do
    case :binary.split(acc, "\r\n\r\n") do
      [head, rest] -> {head, rest}
      [_] -> read_head(socket, acc <> recv(socket))
    end
  end

  def request_line(head), do: head |> String.split("\r\n") |> hd()

  def header(head, name) do
    for line <- head |> String.split("\r\n") |> tl(),
        [key, value] <- [String.split(line, ":", parts: 2)],
        String.downcase(key) == name,
        do: String.trim(value)
  end

  def values(headers, name), do: for({^name, value} <- headers, do: value)

  def read_at_least(_socket, acc, n) when byte_size(acc) >= n, do: acc
  def read_at_least(socket, acc, n), do: read_at_least(socket, acc <> recv(socket), n)

  def dechunk(socket, acc), do: socket |> chunks(acc) |> IO.iodata_to_binary()

  def chunks(socket, acc) do
    acc = read_until(socket, acc, "\r\n")
    [size, rest] = :binary.split(acc, "\r\n")

    case String.to_integer(size, 16) do
      0 ->
        []

      length ->
        <<chunk::binary-size(length), "\r\n", tail::binary>> =
          read_at_least(socket, rest, length + 2)

        [chunk | chunks(socket, tail)]
    end
  end

  def read_response_head(socket) do
    {head, rest} = read_head(socket)
    [status_line | lines] = String.split(head, "\r\n")
    ["HTTP/1." <> _, status | _] = String.split(status_line, " ", parts: 3)

    headers =
      for line <- lines,
          [key, value] <- [String.split(line, ":", parts: 2)],
          do: {String.downcase(key), String.trim(value)}

    {String.to_integer(status), headers, rest}
  end

  def read_response(socket, opts \\ []) do
    {status, headers, rest} = read_response_head(socket)

    body =
      cond do
        opts[:method] == "HEAD" or status in [204, 304] ->
          ""

        values(headers, "transfer-encoding") == ["chunked"] ->
          dechunk(socket, rest)

        true ->
          length = headers |> values("content-length") |> hd() |> String.to_integer()
          binary_part(read_at_least(socket, rest, length), 0, length)
      end

    {status, headers, body}
  end

  def log_for_pid(log, pid) do
    marker = "pid=" <> String.trim_leading(inspect(pid), "#PID")

    log
    |> String.split(~r/\n(?=\d{2}:\d{2}:\d{2}\.\d{3})/)
    |> Enum.filter(&String.contains?(&1, marker))
    |> Enum.join("\n")
  end

  def read_until_closed(socket, acc \\ "") do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} -> read_until_closed(socket, acc <> data)
      {:error, :closed} -> {:closed, acc}
    end
  end

  def ws_request(port, path, headers, host \\ nil) do
    socket = connect(port)

    send_raw(socket, [
      "GET #{path} HTTP/1.1\r\nHost: #{host || "127.0.0.1:#{port}"}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n",
      "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: #{Base.encode64("the sample nonce")}\r\n",
      Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
      "\r\n"
    ])

    socket
  end

  def ws_send_text(socket, text), do: send_frame(socket, 1, text)
  def ws_close(socket, code), do: send_frame(socket, 8, <<code::16>>)

  def ws_recv(socket, acc) do
    case acc do
      <<_::4, opcode::4, 0::1, length::7, payload::binary-size(length), rest::binary>>
      when length < 126 ->
        {{opcode_name(opcode), payload}, rest}

      _ ->
        ws_recv(socket, acc <> recv(socket))
    end
  end

  def server_text_frame(text), do: server_frame(1, text)

  def server_frame(opcode, payload, fin \\ 1),
    do: <<fin::1, 0::3, opcode::4, 0::1, byte_size(payload)::7, payload::binary>>

  defp send_frame(socket, opcode, payload) do
    mask = :crypto.strong_rand_bytes(4)

    masked =
      for {byte, index} <- Enum.with_index(:binary.bin_to_list(payload)),
          into: <<>>,
          do: <<Bitwise.bxor(byte, :binary.at(mask, rem(index, 4)))>>

    send_raw(socket, [<<1::1, 0::3, opcode::4, 1::1, byte_size(payload)::7>>, mask, masked])
  end

  defp opcode_name(1), do: :text
  defp opcode_name(2), do: :binary
  defp opcode_name(8), do: :close
  defp opcode_name(9), do: :ping
  defp opcode_name(10), do: :pong

  defp read_until(socket, acc, marker) do
    if String.contains?(acc, marker),
      do: acc,
      else: read_until(socket, acc <> recv(socket), marker)
  end

  defp recv(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
    data
  end
end
