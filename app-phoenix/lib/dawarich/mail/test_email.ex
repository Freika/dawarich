defmodule Dawarich.Mail.TestEmail do
  @moduledoc false

  alias Dawarich.I18n
  alias Dawarich.Mail.{ExploreFeatures, SmtpConfig}

  def configured?(env),
    do: is_binary(env["SMTP_SERVER"]) and String.trim(env["SMTP_SERVER"]) != ""

  def supported?(env) do
    if configured?(env) do
      options = SmtpConfig.options(env)
      options[:auth] == :never and options[:tls] == :never and options[:ssl] == false
    else
      true
    end
  rescue
    _ -> false
  end

  def run(user, ambient, env, opts \\ []) do
    locale = ExploreFeatures.locale(user.settings, ambient)

    if configured?(env) do
      args = %{"user_id" => user.id, "locale" => locale}
      Oban.insert!(Keyword.get(opts, :oban, Oban), Dawarich.Mail.TestEmailWorker.new(args))
      {:notice, text(locale, "test_email_queued", %{"email" => user.email})}
    else
      {:alert, text(locale, "smtp_not_configured", %{})}
    end
  rescue
    error in ArgumentError ->
      failure(
        ExploreFeatures.locale(user.settings, ambient),
        "ArgumentError: " <> Exception.message(error)
      )

    _error ->
      failure(ExploreFeatures.locale(user.settings, ambient), "IOError")
  catch
    _, _ -> failure(ExploreFeatures.locale(user.settings, ambient), "IOError")
  end

  defp failure(locale, detail),
    do: {:alert, text(locale, "test_email_failed", %{"error" => detail})}

  defp text(locale, key, bindings) do
    {:ok, text} = I18n.t(locale, "controllers.settings.general." <> key, bindings)
    text
  end
end
