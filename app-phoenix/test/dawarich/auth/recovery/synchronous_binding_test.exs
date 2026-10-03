defmodule Dawarich.Auth.Recovery.SynchronousBindingTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Recovery.{Notification, SynchronousBinding}

  test "sends the recovery mail over SMTP through the current transport" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, packet: :line])

    {:ok, port} = :inet.port(listener)
    owner = self()
    Task.start_link(fn -> serve(listener, owner) end)

    notification = %Notification{
      kind: :reset_password_instructions,
      user_id: 7,
      raw: "synthetic-raw",
      digest: "synthetic-digest",
      locale: "en"
    }

    env = %{"E2E_SMTP_PORT" => Integer.to_string(port), "SMTP_FROM" => "auth@dawarich.test"}
    user = %{id: 7, email: "binding@dawarich.test", settings: %{}}

    assert SynchronousBinding.deliver(notification, user, "http://www.example.com", env) == :ok
    assert_receive {:smtp, envelope, data}, 5000
    assert "RCPT TO:<binding@dawarich.test>" in envelope

    assert data =~ "Content-Type: text/plain"

    {"multipart", "alternative", headers, _params, parts} =
      :mimemail.decode(data, encoding: :none)

    {"text", "html", _, _, body} = List.last(parts)

    assert body =~
             ~s(href="http://www.example.com/users/password/edit?reset_password_token=synthetic-raw")

    assert {"Subject", "Reset password instructions"} in headers
    refute List.keymember?(headers, "Reply-To", 0)
  end

  defp serve(listener, owner) do
    {:ok, socket} = :gen_tcp.accept(listener)
    :ok = :gen_tcp.send(socket, "220 sink\r\n")
    converse(socket, owner, [])
  end

  defp converse(socket, owner, envelope) do
    {:ok, line} = :gen_tcp.recv(socket, 0, 5000)
    command = String.trim_trailing(line, "\r\n")

    cond do
      String.starts_with?(command, "DATA") ->
        :ok = :gen_tcp.send(socket, "354 go\r\n")
        send(owner, {:smtp, Enum.reverse(envelope), message(socket, [])})
        :ok = :gen_tcp.send(socket, "250 queued\r\n")
        converse(socket, owner, envelope)

      String.starts_with?(command, "QUIT") ->
        :gen_tcp.send(socket, "221 bye\r\n")
        :gen_tcp.close(socket)

      true ->
        :ok = :gen_tcp.send(socket, "250 ok\r\n")
        converse(socket, owner, [command | envelope])
    end
  end

  defp message(socket, lines) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, ".\r\n"} -> lines |> Enum.reverse() |> IO.iodata_to_binary()
      {:ok, line} -> message(socket, [line | lines])
    end
  end
end
