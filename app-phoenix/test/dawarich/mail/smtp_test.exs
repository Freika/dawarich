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
end
