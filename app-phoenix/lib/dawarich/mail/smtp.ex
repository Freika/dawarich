defmodule Dawarich.Mail.Smtp do
  @moduledoc false
  alias Dawarich.Mail.SmtpConfig

  def deliver(message, env) do
    envelope = {SmtpConfig.envelope_from(message.from), [message.to], encode(message)}

    case :gen_smtp_client.send_blocking(envelope, SmtpConfig.options(env)) do
      receipt when is_binary(receipt) -> :ok
      {:error, type, detail} -> {:error, {type, detail}}
      {:error, reason} -> {:error, reason}
    end
  end

  def encode(message),
    do:
      :mimemail.encode(
        {"multipart", "alternative",
         [{"From", message.from || ""}, {"To", message.to}, {"Subject", message.subject}] ++
           if(message[:message_id], do: [{"Message-ID", message.message_id}], else: []), %{},
         [part("plain", message.text), part("html", message.html)]}
      )

  defp part(subtype, body),
    do: {"text", subtype, [], %{content_type_params: [{"charset", "utf-8"}]}, body}
end
