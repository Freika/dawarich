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
end
