defmodule Dawarich.Mail.SmtpTlsReviewTest do
  use ExUnit.Case, async: true
  alias Dawarich.Mail.Smtp

  @message %{
    from: "sender@example.test",
    to: "recipient@example.test",
    subject: "TLS",
    text: "TLS",
    html: "<p>TLS</p>"
  }

  @tag mail_review: "F2"
  test "implicit TLS and STARTTLS apply verification CA file and recipient server hostname on the wire" do
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
      assert {{:error, _}, false} = deliver(protocol, "localhost", "peer", nil, cert, key)
      assert {{:error, _}, false} = deliver(protocol, "127.0.0.1", "peer", ca, cert, key)
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
        case :gen_tcp.accept(listen, 3000) do
          {:ok, socket} ->
            try do
              if protocol == :implicit do
                upgrade(socket, cert, key)
              else
                :gen_tcp.send(socket, "220 sink ESMTP\r\n")

                with {:ok, "EHLO " <> _} <- :gen_tcp.recv(socket, 0, 3000),
                     :ok <- :gen_tcp.send(socket, "250-sink\r\n250 STARTTLS\r\n"),
                     {:ok, "STARTTLS\r\n"} <- :gen_tcp.recv(socket, 0, 3000),
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
      "SMTP_READ_TIMEOUT" => "1"
    }

    env = if ca, do: Map.put(env, "SMTP_CA_FILE", ca), else: env

    try do
      result = Smtp.deliver(@message, env)
      {result, Task.await(server, 5000)}
    after
      :gen_tcp.close(listen)
    end
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
           3000
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
    case :ssl.recv(socket, 0, 3000) do
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
