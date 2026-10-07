defmodule Dawarich.Mail.SmtpReplyReviewTest do
  use Dawarich.JobsCase

  alias Dawarich.Mail.{Delivery, Smtp}
  alias Dawarich.Test.RawHTTP

  @message %{
    from: "sender@example.test",
    to: "recipient@example.test",
    subject: "Reply review",
    text: "Reply review",
    html: "<p>Reply review</p>"
  }

  @tag smtp_reply: "recipient"
  test "RCPT forwarding and positive completion replies send DATA while negative replies refuse it" do
    for code <- [250, 251, 252] do
      assert {:ok, commands} = deliver(%{recipient: "#{code} will forward\r\n"})
      assert "DATA\r\n" in commands
      assert ".\r\n" in commands
    end

    for code <- [450, 550] do
      assert {{:error, {_, {_, _, {:smtp_status, ^code}}}}, commands} =
               deliver(%{recipient: "#{code} refused\r\n"})

      refute "DATA\r\n" in commands
    end
  end

  @tag smtp_reply: "bare_auth"
  test "bare AUTH 235 and envelope 250 replies complete authenticated delivery" do
    assert {:ok, commands} =
             deliver(%{auth: "235\r\n", sender: "250\r\n", recipient: "250\r\n"})

    assert Enum.any?(commands, &String.starts_with?(&1, "MAIL FROM:"))
    assert ".\r\n" in commands
  end

  @tag smtp_reply: "multiline"
  test "multiline replies accept code-only termination and reject mismatched codes without server text" do
    assert {:ok, commands} =
             deliver(%{
               auth: "235-authenticated\r\n235\r\n",
               recipient: "251-forwarding\r\n251\r\n",
               data: "250-accepted\r\n250\r\n"
             })

    assert ".\r\n" in commands

    assert {{:error, {_, {_, _, :invalid_reply}}} = error, commands} =
             deliver(%{recipient: "250-continuing\r\n251 echoed-server-text\r\n"})

    refute inspect(error) =~ "echoed-server-text"
    refute "DATA\r\n" in commands
  end

  @tag smtp_reply: "data_receipt"
  test "bare post-DATA acceptance records delivery and retry sends no duplicate after QUIT failure" do
    transport = Application.fetch_env!(:dawarich, :mail_transport)
    Application.put_env(:dawarich, :mail_transport, Smtp)
    on_exit(fn -> Application.put_env(:dawarich, :mail_transport, transport) end)

    for quit <- [:close, :reject] do
      sink = sink()
      put_smtp_env(env(sink))
      event_id = Ecto.UUID.generate()
      key = "reply-review:#{quit}"
      owner = self()

      build = fn ->
        send(owner, :built)
        {:ok, @message}
      end

      send_mail = fn ->
        Delivery.deliver(ScratchRepo, "mail.reply-review", key, "record", event_id, build)
      end

      assert {:ok, commands} = exchange(sink, %{data: "250\r\n", quit: quit}, send_mail)
      assert ".\r\n" in commands
      assert_received :built

      assert [[%DateTime{}]] =
               rows(
                 "SELECT delivered_at FROM phoenix.delivery_claims WHERE handler=$1 AND provider_key=$2",
                 ["mail.reply-review", key]
               )

      assert send_mail.() == :ok
      refute_received :built
      assert {:error, :timeout} = :gen_tcp.accept(sink.listen, 0)
    end
  end

  defp sink do
    sink = RawHTTP.listen(packet: :line)
    on_exit(fn -> :gen_tcp.close(sink.listen) end)
    sink
  end

  defp env(sink) do
    %{
      "DAWARICH_RAILS" => "off",
      "SMTP_SERVER" => "127.0.0.1",
      "SMTP_PORT" => Integer.to_string(sink.port),
      "SMTP_AUTHENTICATION" => "plain",
      "SMTP_USERNAME" => "fixture-user",
      "SMTP_PASSWORD" => "fixture-password",
      "SMTP_STARTTLS" => "false"
    }
  end

  defp put_smtp_env(env) do
    keys = Map.keys(env) ++ ~w(E2E_SMTP_PORT SMTP_SSL SMTP_TLS SMTP_OPENSSL_VERIFY_MODE)
    previous = Map.take(System.get_env(), keys)
    Enum.each(keys, &System.delete_env/1)
    System.put_env(env)

    on_exit(fn ->
      Enum.each(keys, &System.delete_env/1)
      System.put_env(previous)
    end)
  end

  defp deliver(replies) do
    sink = sink()
    exchange(sink, replies, fn -> Smtp.deliver(@message, env(sink)) end)
  end

  defp exchange(sink, replies, deliver) do
    client = Task.async(fn -> receive do: (:deliver -> deliver.()) end)
    {socket, _} = RawHTTP.accept_on_request(sink, fn -> send(client.pid, :deliver) end)
    RawHTTP.reply(socket, "220 sink ESMTP\r\n")
    commands = serve(socket, replies, :command, [])
    :gen_tcp.close(socket)
    {Task.await(client, :infinity), Enum.reverse(commands)}
  end

  defp serve(socket, replies, state, commands) do
    case :gen_tcp.recv(socket, 0, :infinity) do
      {:ok, line} ->
        {answer, next} = answer(line, replies, state)
        if answer, do: RawHTTP.reply(socket, answer)

        if next == :done,
          do: [line | commands],
          else: serve(socket, replies, next, [line | commands])

      {:error, :closed} ->
        commands
    end
  end

  defp answer("EHLO " <> _, _, _), do: {"250-sink\r\n250 AUTH PLAIN\r\n", :command}
  defp answer("AUTH " <> _, replies, _), do: {replies[:auth] || "235 accepted\r\n", :command}
  defp answer("MAIL FROM:" <> _, replies, _), do: {replies[:sender] || "250 ok\r\n", :command}

  defp answer("RCPT TO:" <> _, replies, _),
    do: {replies[:recipient] || "250 ok\r\n", :command}

  defp answer("DATA\r\n", _, _), do: {"354 go\r\n", :data}

  defp answer(".\r\n", replies, :data),
    do:
      {replies[:data] || "250 queued\r\n",
       if(replies[:quit] == :close, do: :done, else: :command)}

  defp answer(_, _, :data), do: {nil, :data}
  defp answer("QUIT\r\n", %{quit: :reject}, _), do: {"421 unavailable\r\n", :done}
  defp answer("QUIT\r\n", _, _), do: {"221 bye\r\n", :done}
end
