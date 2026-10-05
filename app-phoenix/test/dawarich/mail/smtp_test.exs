defmodule Dawarich.Mail.SmtpTest do
  use ExUnit.Case, async: true

  test "encodes one multipart alternative message with UTF-8 text and HTML parts and a readable subject" do
    message = %{
      from: "Dawarich <hi@example.test>",
      to: "u@example.test",
      subject: "Entdecke Dawarich – Funktionen",
      text: "Hallo ü",
      html: "<p>Hallo ü</p>"
    }

    {"multipart", "alternative", headers, _params, [text, html]} =
      message |> Dawarich.Mail.Smtp.encode() |> :mimemail.decode(encoding: :none)

    assert {"Subject", subject} = List.keyfind(headers, "Subject", 0)

    assert subject
           |> String.replace_prefix("=?UTF-8?Q?", "")
           |> String.replace_suffix("?=", "")
           |> String.replace("_", " ")
           |> :mimemail.decode_quoted_printable() == "Entdecke Dawarich – Funktionen"

    assert {"To", "u@example.test"} in headers
    assert {"text", "plain", _, _, "Hallo ü"} = text
    assert {"text", "html", _, _, "<p>Hallo ü</p>"} = html
  end

  describe "HTML-only mail" do
    alias Dawarich.Mail.Smtp
    alias Dawarich.Test.MailWire

    test "frames each Devise recovery mail as Rails does" do
      for entry <- MailWire.fixture()["mails"] do
        message = %{
          from: entry["from"],
          reply_to: entry["reply_to"],
          to: entry["to"],
          subject: entry["subject"],
          html: entry["html"],
          format: :html_only
        }

        assert MailWire.phoenix(message) == MailWire.rails(entry),
               entry["kind"] <> " " <> entry["locale"]
      end
    end

    test "matches Mail 2.9.1 on every newline, charset and transfer-encoding edge" do
      for {name, entry} <- MailWire.fixture()["controls"] do
        message = %{
          from: "Dawarich <a11a@dawarich.test>",
          to: "control@dawarich.test",
          subject: "Control",
          html: entry["html"],
          format: :html_only
        }

        assert MailWire.phoenix(message) == MailWire.rails(entry), name
      end
    end

    test "multipart mail keeps its bytes" do
      message = %{
        from: "a@dawarich.test",
        to: "b@dawarich.test",
        subject: "s",
        text: "t",
        html: "<p>h</p>",
        message_id: "<m@dawarich.test>"
      }

      stable = fn wire ->
        wire
        |> String.replace(~r/^Date: [^\r]*\r\n/m, "")
        |> String.replace(~r/_=[0-9a-z]+=_/, "_=boundary=_")
      end

      assert stable.(Smtp.data(message)) == stable.(Smtp.encode(message))
    end
  end

  describe "deliver/2" do
    import Dawarich.Test.RawHTTP, only: [listen: 0, accept_on_request: 2, reply: 2]

    alias Dawarich.Mail.Smtp
    alias Dawarich.Test.MailWire

    defp serve(socket) do
      reply(socket, "220 sink ESMTP\r\n")

      for answer <- ["250 sink\r\n", "250 ok\r\n", "250 ok\r\n", "354 go\r\n"] do
        {:ok, _command} = :gen_tcp.recv(socket, 0, 5_000)
        reply(socket, answer)
      end

      data = receive_data(socket, "")
      reply(socket, "250 queued\r\n")
      {:ok, "QUIT\r\n"} = :gen_tcp.recv(socket, 0, 5_000)
      reply(socket, "221 bye\r\n")
      data
    end

    defp receive_data(socket, acc) do
      if String.ends_with?(acc, "\r\n.\r\n") do
        acc |> binary_part(0, byte_size(acc) - 3) |> String.replace(~r/^\.\./m, ".")
      else
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
        receive_data(socket, acc <> chunk)
      end
    end

    defp delivered(message) do
      sink = listen()
      on_exit(fn -> :gen_tcp.close(sink.listen) end)
      env = %{"E2E_SMTP_PORT" => Integer.to_string(sink.port)}

      client = Task.async(fn -> receive do: (:deliver -> Smtp.deliver(message, env)) end)
      {socket, :deliver} = accept_on_request(sink, fn -> send(client.pid, :deliver) end)
      data = serve(socket)
      assert Task.await(client, :infinity) == :ok
      data
    end

    defp html_only(fields),
      do: Map.merge(%{to: "control@dawarich.test", format: :html_only}, Map.new(fields))

    test "puts on the wire what Rails sends: one trailing CRLF, no stray soft break" do
      fixture = MailWire.fixture()

      devise =
        for entry <- fixture["mails"], entry["transfer"] in ["7bit", "quoted-printable"] do
          message =
            html_only(
              from: entry["from"],
              reply_to: entry["reply_to"],
              to: entry["to"],
              subject: entry["subject"],
              html: entry["html"]
            )

          {entry["kind"] <> " " <> entry["locale"], message, entry}
        end

      controls =
        for name <- ~w(ascii_one qp_none qp_one dots), entry = fixture["controls"][name] do
          message =
            html_only(
              from: "Dawarich <a11a@dawarich.test>",
              subject: "Control",
              html: entry["html"]
            )

          {name, message, entry}
        end

      for {name, message, entry} <- devise ++ controls do
        assert MailWire.decode(delivered(message)) == MailWire.rails(entry), name
      end
    end
  end
end
