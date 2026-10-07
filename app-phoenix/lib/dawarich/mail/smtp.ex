defmodule Dawarich.Mail.Smtp do
  @moduledoc false
  alias Dawarich.Mail.SmtpConfig

  def deliver(message, env) do
    envelope = {SmtpConfig.envelope_from(message.from), [message.to], data(message)}

    options = SmtpConfig.options(env)

    result =
      Task.async(fn -> :gen_smtp_client.send_blocking(envelope, options) end)
      |> Task.await(:infinity)

    case result do
      receipt when is_binary(receipt) -> :ok
      {:error, type, detail} -> {:error, {type, detail}}
      {:error, reason} -> {:error, reason}
    end
  end

  def data(%{format: :html_only} = message) do
    transfer = transfer_encoding(message.html)
    encoded = html_only(message, transfer)
    size = byte_size(encoded)

    cond do
      binary_part(encoded, size - 2, 2) == "\r\n" -> binary_part(encoded, 0, size - 2)
      transfer == "quoted-printable" -> encoded <> "="
      true -> encoded
    end
  end

  def data(message), do: encode(message)

  def encode(%{format: :html_only} = message),
    do: html_only(message, transfer_encoding(message.html))

  def encode(message),
    do:
      :mimemail.encode(
        {"multipart", "alternative", headers(message), %{},
         [part("plain", message.text), part("html", message.html)]}
      )

  defp html_only(message, transfer) do
    body = if transfer == "base64", do: message.html, else: crlf(message.html)
    params = %{content_type_params: [{"charset", "UTF-8"}], transfer_encoding: transfer}

    :mimemail.encode(
      {"text", "html", headers(message) ++ [{"Content-Transfer-Encoding", transfer}], params,
       body}
    )
  end

  defp headers(message),
    do:
      [{"From", message.from || ""}, {"To", message.to}, {"Subject", message.subject}] ++
        if(message[:reply_to], do: [{"Reply-To", message.reply_to}], else: []) ++
        if(message[:message_id], do: [{"Message-ID", message.message_id}], else: [])

  defp transfer_encoding(body) do
    bytes = :binary.bin_to_list(body)

    lines_fit? =
      Regex.scan(~r/[^\n]*\n|[^\n]+\z/, body)
      |> Enum.all?(fn [line] -> byte_size(line) <= 998 end)

    printable = Enum.count(bytes, &(&1 in [9, 10, 13] or &1 in 32..60 or &1 in 62..126))
    quoted = 3 * (byte_size(body) - printable) + printable

    cond do
      Enum.all?(bytes, &(&1 < 128)) and lines_fit? -> "7bit"
      3 * quoted <= 4 * byte_size(body) -> "quoted-printable"
      true -> "base64"
    end
  end

  defp crlf(body), do: String.replace(body, ~r/\r\n|\r|\n/, "\r\n")

  defp part(subtype, body),
    do: {"text", subtype, [], %{content_type_params: [{"charset", "utf-8"}]}, body}
end
