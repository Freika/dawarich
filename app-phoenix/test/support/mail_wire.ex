defmodule Dawarich.Test.MailWire do
  @moduledoc false

  alias Dawarich.Mail.{Smtp, SmtpConfig}

  @fixture Path.expand("../fixtures/auth/activation.json", __DIR__)

  def fixture, do: @fixture |> File.read!() |> Jason.decode!()

  def phoenix(message), do: decode(Smtp.data(message) <> "\r\n")

  def rails(entry), do: entry["wire"] |> Base.decode64!() |> decode()

  def decode(wire) do
    {type, subtype, headers, params, body} = :mimemail.decode(wire, encoding: :none)

    value = fn name ->
      Enum.find_value(headers, fn {key, v} -> String.downcase(key) == name && unfold(v) end)
    end

    %{
      type: {String.downcase(type), String.downcase(subtype)},
      charset:
        params
        |> Map.get(:content_type_params, [])
        |> Enum.find_value(fn {k, v} -> String.downcase(k) == "charset" && String.downcase(v) end),
      transfer: downcase(value.("content-transfer-encoding")),
      subject: words(value.("subject")),
      from: address(value.("from")),
      reply_to: address(value.("reply-to")),
      to: address(value.("to")),
      names: headers |> Enum.map(&String.downcase(elem(&1, 0))) |> Enum.sort(),
      body: body
    }
  end

  defp unfold(value), do: String.replace(value, ~r/\r\n[ \t]+/, " ")

  defp downcase(nil), do: nil
  defp downcase(value), do: String.downcase(value)

  defp words(nil), do: nil

  defp words(value) do
    Regex.replace(~r/=\?utf-8\?([qb])\?([^?]*)\?=(?:\s+(?==\?))?/i, value, fn _, encoding, text ->
      if String.downcase(encoding) == "q",
        do: text |> String.replace("_", "=20") |> :mimemail.decode_quoted_printable(),
        else: Base.decode64!(text)
    end)
  end

  defp address(nil), do: nil

  defp address(value) do
    decoded = words(value)

    {decoded |> String.split("<") |> hd() |> String.trim() |> String.trim(~s(")),
     SmtpConfig.envelope_from(decoded)}
  end
end
