defmodule Dawarich.Mail.SmtpAuthentication do
  @moduledoc false
  alias Dawarich.Mail.SmtpTransport

  def authenticate(socket, options) do
    user = to_string(options[:username])
    secret = to_string(options[:password])
    timeout = options[:timeout]

    case options[:auth_mechanism] do
      "plain" ->
        finish(
          socket,
          "AUTH PLAIN " <> Base.encode64(<<0, user::binary, 0, secret::binary>>),
          timeout
        )

      "xoauth2" ->
        token = "user=#{user}\x01auth=Bearer #{secret}\x01\x01"
        finish(socket, "AUTH XOAUTH2 " <> Base.encode64(token), timeout)

      "login" ->
        exchange(socket, "AUTH LOGIN", 334, timeout)
        exchange(socket, Base.encode64(user), 334, timeout)
        finish(socket, Base.encode64(secret), timeout)

      "cram_md5" ->
        challenge = exchange(socket, "AUTH CRAM-MD5", 334, timeout) |> hd()

        case Base.decode64(challenge) do
          {:ok, decoded} ->
            digest = :crypto.mac(:hmac, :md5, secret, decoded) |> Base.encode16(case: :lower)
            finish(socket, Base.encode64(user <> " " <> digest), timeout)

          :error ->
            refused()
        end

      _ ->
        refused()
    end
  end

  defp finish(socket, line, timeout), do: exchange(socket, line, 235, timeout)

  defp exchange(socket, line, expected, timeout) do
    SmtpTransport.command(socket, line, expected, timeout)
  catch
    {:smtp_failure, :network_failure, reason} -> throw({:smtp_failure, :network_failure, reason})
    {:smtp_failure, _, _} -> refused()
  end

  defp refused, do: throw({:smtp_failure, :permanent_failure, :auth_failed})
end
