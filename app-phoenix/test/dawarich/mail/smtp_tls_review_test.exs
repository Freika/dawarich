defmodule Dawarich.Mail.SmtpTlsReviewTest do
  use ExUnit.Case, async: true
  alias Dawarich.Mail.{Smtp, SmtpConfig}

  @message %{
    from: "sender@example.test",
    to: "recipient@example.test",
    subject: "TLS",
    text: "TLS",
    html: "<p>TLS</p>"
  }

  @tag mail_review: "F2"
  test "implicit TLS and STARTTLS verify CA and hostname independently of configured read deadlines" do
    dir = Path.join(System.tmp_dir!(), "mail-tls-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    cert = Path.join(dir, "cert.pem")
    key = Path.join(dir, "key.pem")

    ca = Path.join(dir, "ca.pem")
    ca_key = Path.join(dir, "ca-key.pem")
    csr = Path.join(dir, "server.csr")
    ext = Path.join(dir, "server.ext")

    File.write!(
      ext,
      "subjectAltName=DNS:localhost\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n"
    )

    openssl!([
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-keyout",
      ca_key,
      "-out",
      ca,
      "-days",
      "1",
      "-subj",
      "/CN=Mail test CA",
      "-addext",
      "basicConstraints=critical,CA:TRUE"
    ])

    openssl!([
      "req",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-keyout",
      key,
      "-out",
      csr,
      "-subj",
      "/CN=localhost"
    ])

    openssl!([
      "x509",
      "-req",
      "-in",
      csr,
      "-CA",
      ca,
      "-CAkey",
      ca_key,
      "-CAcreateserial",
      "-out",
      cert,
      "-days",
      "1",
      "-extfile",
      ext
    ])

    for protocol <- [:implicit, :starttls] do
      assert {:ok, true} = deliver(protocol, "localhost", "none", nil, cert, key)
      assert {:ok, true} = deliver(protocol, "localhost", "peer", ca, cert, key)
      assert {{:error, untrusted}, false} = deliver(protocol, "localhost", "peer", nil, cert, key)
      assert inspect(untrusted) =~ "unknown_ca"
      assert {{:error, mismatch}, false} = deliver(protocol, "127.0.0.1", "peer", ca, cert, key)
      assert inspect(mismatch) =~ "hostname_check_failed"
    end
  end

  test "configured read timeout closes an implicit TLS connection whose server never responds" do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])

    on_exit(fn -> :gen_tcp.close(listen) end)
    {:ok, {_, port}} = :inet.sockname(listen)

    env = %{
      "SMTP_SERVER" => "127.0.0.1",
      "SMTP_PORT" => to_string(port),
      "SMTP_SSL" => "true",
      "SMTP_STARTTLS" => "false",
      "SMTP_AUTHENTICATION" => "none",
      "SMTP_READ_TIMEOUT" => "1"
    }

    client = Task.async(fn -> Smtp.deliver(@message, env) end)
    {:ok, socket} = :gen_tcp.accept(listen, :infinity)

    try do
      assert :ok = await_close(socket)

      assert {:error, {:retries_exceeded, {:network_failure, ~c"127.0.0.1", {:error, :timeout}}}} =
               Task.await(client, :infinity)
    after
      :gen_tcp.close(socket)
    end
  end

  defp await_close(socket) do
    case :gen_tcp.recv(socket, 0, :infinity) do
      {:ok, _hello} -> await_close(socket)
      {:error, :closed} -> :ok
    end
  end

  defp openssl!(args) do
    {_output, status} = System.cmd("openssl", args, stderr_to_stdout: true)
    assert status == 0
  end

  defp deliver(protocol, hostname, mode, ca, cert, key) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :line, active: false, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listen)

    server =
      Task.async(fn ->
        case :gen_tcp.accept(listen, :infinity) do
          {:ok, socket} ->
            try do
              if protocol == :implicit do
                upgrade(socket, cert, key)
              else
                :gen_tcp.send(socket, "220 sink ESMTP\r\n")

                with {:ok, "EHLO " <> _} <- :gen_tcp.recv(socket, 0, :infinity),
                     :ok <- :gen_tcp.send(socket, "250-sink\r\n250 STARTTLS\r\n"),
                     {:ok, "STARTTLS\r\n"} <- :gen_tcp.recv(socket, 0, :infinity),
                     :ok <- :gen_tcp.send(socket, "220 upgrade\r\n") do
                  upgrade(socket, cert, key, false)
                else
                  _ -> false
                end
              end
            after
              :gen_tcp.close(socket)
            end

          _ ->
            false
        end
      end)

    env = %{
      "SMTP_SERVER" => hostname,
      "SMTP_PORT" => to_string(port),
      "SMTP_SSL" => to_string(protocol == :implicit),
      "SMTP_STARTTLS" => "true",
      "SMTP_AUTHENTICATION" => "none",
      "SMTP_OPENSSL_VERIFY_MODE" => mode,
      "SMTP_READ_TIMEOUT" => "0"
    }

    env = if ca, do: Map.put(env, "SMTP_CA_FILE", ca), else: env

    try do
      result = wire_deliver(SmtpConfig.options(env))
      {result, Task.await(server, :infinity)}
    after
      :gen_tcp.close(listen)
    end
  end

  defp wire_deliver(options) do
    with {:ok, socket} <- connect(options) do
      try do
        if options[:ssl], do: assert({:ok, "220 sink ESMTP\r\n"} = :smtp_socket.recv(socket, 0))
        command(socket, "EHLO localhost\r\n", "250")
        command(socket, "MAIL FROM:<#{@message.from}>\r\n", "250")
        command(socket, "RCPT TO:<#{@message.to}>\r\n", "250")
        command(socket, "DATA\r\n", "354")
        command(socket, Smtp.data(@message) <> "\r\n.\r\n", "250")
        command(socket, "QUIT\r\n", "221")
        :ok
      after
        :smtp_socket.close(socket)
      end
    end
  end

  defp connect(options) do
    if options[:ssl] do
      :smtp_socket.connect(
        :ssl,
        options[:relay],
        options[:port],
        [:binary | options[:sockopts]],
        :infinity
      )
    else
      {:ok, socket} =
        :smtp_socket.connect(:tcp, options[:relay], options[:port], [:binary], :infinity)

      try do
        assert {:ok, "220 sink ESMTP\r\n"} = :smtp_socket.recv(socket, 0)
        :ok = :smtp_socket.send(socket, "EHLO localhost\r\n")
        assert {:ok, "250-sink\r\n"} = :smtp_socket.recv(socket, 0)
        assert {:ok, "250 STARTTLS\r\n"} = :smtp_socket.recv(socket, 0)
        command(socket, "STARTTLS\r\n", "220")
        :smtp_socket.to_ssl_client(socket, [:binary | options[:tls_options]], :infinity)
      catch
        kind, reason ->
          :smtp_socket.close(socket)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  defp command(socket, line, code) do
    assert :ok = :smtp_socket.send(socket, line)
    assert {:ok, <<^code::binary-size(3), _rest::binary>>} = :smtp_socket.recv(socket, 0)
  end

  defp upgrade(socket, cert, key, greeting \\ true) do
    case :ssl.handshake(
           socket,
           [
             certfile: String.to_charlist(cert),
             keyfile: String.to_charlist(key),
             verify: :verify_none,
             active: false,
             packet: :line
           ],
           :infinity
         ) do
      {:ok, secure} ->
        try do
          if greeting, do: :ssl.send(secure, "220 sink ESMTP\r\n")
          serve(secure, :command, false)
        after
          :ssl.close(secure)
        end

      _ ->
        false
    end
  end

  defp serve(socket, state, accepted) do
    case :ssl.recv(socket, 0, :infinity) do
      {:ok, line} ->
        {reply, next, accepted} = answer(line, state, accepted)
        if reply, do: :ssl.send(socket, reply)
        if next == :done, do: accepted, else: serve(socket, next, accepted)

      _ ->
        accepted
    end
  end

  defp answer("EHLO " <> _, _, accepted), do: {"250 sink\r\n", :command, accepted}
  defp answer("DATA\r\n", _, accepted), do: {"354 go\r\n", :data, accepted}
  defp answer(".\r\n", :data, _), do: {"250 queued\r\n", :command, true}
  defp answer(_, :data, accepted), do: {nil, :data, accepted}
  defp answer("QUIT\r\n", _, accepted), do: {"221 bye\r\n", :done, accepted}
  defp answer(_, _, accepted), do: {"250 ok\r\n", :command, accepted}
end
