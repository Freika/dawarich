defmodule Dawarich.Mail.SmtpPolicyTest do
  use ExUnit.Case, async: true

  alias Dawarich.Mail.{Smtp, SmtpConfig}
  alias Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog

  @message %{
    from: "sender@example.test",
    to: "recipient@example.test",
    subject: "Policy",
    text: "Policy",
    html: "<p>Policy</p>"
  }

  @tag smtp_admission: true
  test "SMTP admission preserves XOAUTH2 Rails ownership until standalone" do
    env = %{
      "SMTP_SERVER" => "smtp.example.test",
      "SMTP_FROM" => "sender@example.test",
      "SMTP_AUTHENTICATION" => " XOAUTH2 ",
      "DOMAIN" => "dawarich.example.test",
      "RAILS_ENV" => "production"
    }

    refute Dawarich.Mail.TestEmail.supported?(env)
    refute Dawarich.Auth.Recovery.MailWorker.deliverable?(env)
    standalone = Map.put(env, "DAWARICH_RAILS", "off")
    assert Dawarich.Mail.TestEmail.supported?(standalone)
    assert Dawarich.Auth.Recovery.MailWorker.deliverable?(standalone)
  end

  @tag a12f3b_case: "M01Unsupported", smtp_policy: "unsupported"
  test "unsupported Rails authentication refuses before connection including the E2E sink" do
    for mechanism <- ~w(digest_md5 gssapi ntlm),
        env <- [
          %{"E2E_SMTP_PORT" => "2525"},
          %{"SMTP_SERVER" => "127.0.0.1"}
        ] do
      env = Map.put(env, "SMTP_AUTHENTICATION", mechanism)

      error = assert_raise ArgumentError, fn -> SmtpConfig.options(env) end
      assert Exception.message(error) =~ "SMTP_AUTHENTICATION=#{mechanism}"
      assert Exception.message(error) =~ "native mail refuses delivery"
      assert Exception.message(error) =~ "no authentication or TLS fallback"
    end

    for policy <- [
          %{"SMTP_AUTHENTICATION" => "plain"},
          %{"SMTP_AUTHENTICATION" => "xoauth2"},
          %{"SMTP_SSL" => "true"},
          %{"SMTP_SSL" => " true "},
          %{"SMTP_USERNAME" => "fixture-user"},
          %{"SMTP_PASSWORD" => "fixture-password"},
          %{"SMTP_STARTTLS" => "true"}
        ] do
      assert_raise ArgumentError, ~r/E2E SMTP sink cannot enforce/, fn ->
        SmtpConfig.options(Map.put(policy, "E2E_SMTP_PORT", "2525"))
      end
    end
  end

  @tag a12f3b_case: "M01Negotiation", smtp_policy: "negotiation"
  test "native SMTP preserves required TLS without authentication fallback" do
    for mechanism <- ~w(plain login cram_md5 xoauth2) do
      wire = mechanism |> String.upcase() |> String.replace("_", "-")
      env = %{"SMTP_AUTHENTICATION" => mechanism, "SMTP_STARTTLS" => "false"}
      assert {:ok, commands} = deliver(env, wire, :accept)
      assert Enum.any?(commands, &String.starts_with?(&1, "AUTH #{wire}"))
      assert Enum.any?(commands, &String.starts_with?(&1, "MAIL FROM:"))

      assert {{:error, _}, commands} = deliver(env, wire, :reject)
      assert Enum.count(commands, &String.starts_with?(&1, "AUTH ")) == 1
      refute Enum.any?(commands, &String.starts_with?(&1, "MAIL FROM:"))

      assert {{:error, _}, commands} =
               deliver(Map.put(env, "SMTP_STARTTLS", "true"), wire, :accept)

      refute Enum.any?(commands, &String.starts_with?(&1, "AUTH "))
      refute Enum.any?(commands, &String.starts_with?(&1, "MAIL FROM:"))
    end
  end

  for mechanism <- ~w(plain login cram_md5 xoauth2) do
    @tag configured_auth: mechanism
    test "configured #{mechanism} is forced on multi-mechanism SMTP without fallback" do
      mechanism = unquote(mechanism)
      wire = mechanism |> String.upcase() |> String.replace("_", "-")

      env = %{
        "DAWARICH_RAILS" => "off",
        "SMTP_AUTHENTICATION" => " #{String.upcase(mechanism)} ",
        "SMTP_STARTTLS" => "false"
      }

      for advertised <- ["CRAM-MD5 LOGIN PLAIN XOAUTH2", "XOAUTH2 PLAIN LOGIN CRAM-MD5", wire, ""] do
        assert {:ok, commands} = deliver(env, advertised, :accept)
        assert Enum.filter(commands, &String.starts_with?(&1, "AUTH ")) == [auth_line(wire)]
        assert Enum.any?(commands, &String.starts_with?(&1, "MAIL FROM:"))
        assert_credentials(wire, commands)
      end

      assert {{:error, _}, commands} = deliver(env, "CRAM-MD5 LOGIN PLAIN XOAUTH2", :reject)
      assert Enum.filter(commands, &String.starts_with?(&1, "AUTH ")) == [auth_line(wire)]
      refute Enum.any?(commands, &String.starts_with?(&1, "MAIL FROM:"))

      assert {{:error, _}, commands} =
               deliver(env, "CRAM-MD5 LOGIN PLAIN XOAUTH2", :reject_response)

      assert Enum.count(commands, &String.starts_with?(&1, "AUTH ")) == 1
      refute Enum.any?(commands, &String.starts_with?(&1, "MAIL FROM:"))

      log =
        capture_log(fn ->
          assert {{:error, reason}, _} =
                   deliver(env, "CRAM-MD5 LOGIN PLAIN XOAUTH2", :echo_reject)

          refute inspect(reason) =~ "fixture-password"
          refute inspect(reason) =~ "fixture-user"
        end)

      refute log =~ "fixture-password"
      refute log =~ "fixture-user"
    end
  end

  defp auth_line("PLAIN"),
    do: "AUTH PLAIN #{Base.encode64("\0fixture-user\0fixture-password")}\r\n"

  defp auth_line("XOAUTH2"),
    do:
      "AUTH XOAUTH2 #{Base.encode64("user=fixture-user\x01auth=Bearer fixture-password\x01\x01")}\r\n"

  defp auth_line(wire), do: "AUTH #{wire}\r\n"

  defp assert_credentials("LOGIN", commands) do
    assert "#{Base.encode64("fixture-user")}\r\n" in commands
    assert "#{Base.encode64("fixture-password")}\r\n" in commands
  end

  defp assert_credentials("CRAM-MD5", commands) do
    digest =
      :crypto.mac(:hmac, :md5, "fixture-password", "challenge") |> Base.encode16(case: :lower)

    assert "#{Base.encode64("fixture-user " <> digest)}\r\n" in commands
  end

  defp assert_credentials(_, _), do: :ok

  defp deliver(env, advertised, outcome) do
    sink = RawHTTP.listen(packet: :line)
    on_exit(fn -> :gen_tcp.close(sink.listen) end)

    env =
      Map.merge(env, %{
        "SMTP_SERVER" => "127.0.0.1",
        "SMTP_PORT" => Integer.to_string(sink.port),
        "SMTP_USERNAME" => "fixture-user",
        "SMTP_PASSWORD" => "fixture-password"
      })

    client = Task.async(fn -> receive do: (:deliver -> Smtp.deliver(@message, env)) end)
    {socket, _} = RawHTTP.accept_on_request(sink, fn -> send(client.pid, :deliver) end)
    RawHTTP.reply(socket, "220 sink ESMTP\r\n")
    commands = serve(socket, advertised, outcome, :command, [])
    :gen_tcp.close(socket)
    {Task.await(client, :infinity), Enum.reverse(commands)}
  end

  defp serve(socket, advertised, outcome, state, commands) do
    case :gen_tcp.recv(socket, 0, :infinity) do
      {:ok, line} ->
        {answer, next} = answer(line, advertised, outcome, state)
        if answer, do: RawHTTP.reply(socket, answer)

        if next == :done,
          do: [line | commands],
          else: serve(socket, advertised, outcome, next, [line | commands])

      {:error, :closed} ->
        commands
    end
  end

  defp answer("EHLO " <> _, advertised, _, _),
    do: {"250-sink\r\n250 AUTH #{advertised}\r\n", :command}

  defp answer("QUIT\r\n", _, _, _), do: {"221 bye\r\n", :done}

  defp answer("AUTH " <> _, _, :echo_reject, _),
    do: {"535 fixture-user fixture-password\r\n", :command}

  defp answer("AUTH " <> _, _, :reject, _), do: {"535 refused\r\n", :command}
  defp answer("AUTH LOGIN\r\n", _, _, _), do: {"334 VXNlcm5hbWU6\r\n", :username}
  defp answer(_, _, _, :username), do: {"334 UGFzc3dvcmQ6\r\n", :password}

  defp answer("AUTH CRAM-MD5\r\n", _, _, _),
    do: {"334 #{Base.encode64("challenge")}\r\n", :password}

  defp answer(_, _, :reject_response, :password), do: {"535 refused\r\n", :command}
  defp answer(_, _, _, :password), do: {"235 accepted\r\n", :command}
  defp answer("AUTH PLAIN " <> _, _, :reject_response, _), do: {"334 continue\r\n", :password}
  defp answer("AUTH XOAUTH2 " <> _, _, :reject_response, _), do: {"334 continue\r\n", :password}
  defp answer("AUTH PLAIN " <> _, _, _, _), do: {"235 accepted\r\n", :command}
  defp answer("AUTH XOAUTH2 " <> _, _, _, _), do: {"235 accepted\r\n", :command}
  defp answer("DATA\r\n", _, _, _), do: {"354 go\r\n", :data}
  defp answer(".\r\n", _, _, :data), do: {"250 queued\r\n", :command}
  defp answer(_, _, _, :data), do: {nil, :data}
  defp answer(_, _, _, _), do: {"250 ok\r\n", :command}
end
