defmodule Dawarich.Mail.TestEmail do
  @moduledoc false

  alias Dawarich.{I18n, TimeZoneName, UserTimeZone}
  alias Dawarich.Mail.{ExploreFeatures, Residual, SmtpConfig}

  @safe ~w(SocketError Timeout::Error OpenSSL::SSL::SSLError Errno::ECONNREFUSED ArgumentError Net::SMTPAuthenticationError Net::SMTPFatalError Net::SMTPServerBusy Net::SMTPSyntaxError Net::SMTPUnknownError)

  def configured?(env),
    do: is_binary(env["SMTP_SERVER"]) and String.trim(env["SMTP_SERVER"]) != ""

  def supported?(env) do
    if configured?(env), do: SmtpConfig.options(env)
    true
  rescue
    _ -> false
  end

  def run(user, ambient, env, opts \\ []) do
    locale = ExploreFeatures.locale(user.settings, ambient)

    if configured?(env) do
      clock =
        Keyword.get_lazy(opts, :clock, fn ->
          clock(user.settings, env, Keyword.get_lazy(opts, :now, &DateTime.utc_now/0))
        end)

      message = Residual.message(:test_email, user, ambient, env, clock: clock)
      transport = Application.get_env(:dawarich, :mail_transport, Dawarich.Mail.Smtp)

      case transport.deliver(message, env) do
        :ok -> {:notice, text(locale, "test_email_sent", %{"email" => user.email})}
        {:error, reason} -> failure(locale, description(reason))
      end
    else
      {:alert, text(locale, "smtp_not_configured", %{})}
    end
  rescue
    error in ArgumentError ->
      failure(
        ExploreFeatures.locale(user.settings, ambient),
        description({"ArgumentError", Exception.message(error)})
      )

    _error ->
      failure(ExploreFeatures.locale(user.settings, ambient), "IOError")
  catch
    _, _ -> failure(ExploreFeatures.locale(user.settings, ambient), "IOError")
  end

  defp clock(settings, env, now) do
    zone = UserTimeZone.zone(settings, env) |> TimeZoneName.to_iana()

    %{rows: [[local, offset, name, valid]]} =
      UserTimeZone.query!(
        "SELECT ($1::timestamptz AT TIME ZONE z.name)::timestamp, " <>
          "extract(epoch FROM (($1::timestamptz AT TIME ZONE z.name) - ($1::timestamptz AT TIME ZONE 'UTC')))::int, " <>
          "z.name, EXISTS(SELECT 1 FROM pg_timezone_names WHERE name = $2) FROM z",
        [now, zone],
        settings,
        env
      )

    %{local: local, offset: offset, zone: name, valid: valid}
  end

  defp description({class, detail}) when class in @safe and is_binary(detail),
    do: class <> ": " <> detail

  defp description({"IOError", _}), do: "IOError"
  defp description({_type, {:network_failure, _host, {:error, :timeout}}}), do: "Timeout::Error"

  defp description({_type, {:network_failure, _host, {:error, :econnrefused}}}),
    do: "Errno::ECONNREFUSED"

  defp description({_type, {:network_failure, _host, {:error, :nxdomain}}}), do: "SocketError"

  defp description({_type, {:permanent_failure, _host, :auth_failed}}),
    do: "Net::SMTPAuthenticationError"

  defp description({_type, {:temporary_failure, _host, :tls_failed}}),
    do: "OpenSSL::SSL::SSLError"

  defp description(_), do: "IOError"

  defp failure(locale, detail),
    do: {:alert, text(locale, "test_email_failed", %{"error" => detail})}

  defp text(locale, key, bindings) do
    {:ok, text} = I18n.t(locale, "controllers.settings.general." <> key, bindings)
    text
  end
end
