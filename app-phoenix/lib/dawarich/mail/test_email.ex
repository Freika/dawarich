defmodule Dawarich.Mail.TestEmail do
  @moduledoc false

  alias Dawarich.I18n
  alias Dawarich.Mail.{ExploreFeatures, SmtpConfig}

  def configured?(env),
    do: is_binary(env["SMTP_SERVER"]) and String.trim(env["SMTP_SERVER"]) != ""

  def supported?(env) do
    if configured?(env) do
      SmtpConfig.admitted?(env)
    else
      true
    end
  rescue
    _ -> false
  end

  def run(user, ambient, env, opts \\ []) do
    locale = ExploreFeatures.locale(Dawarich.UserSettings.get(user), ambient)

    cond do
      Map.get(user, :admin) != true ->
        {:alert, authorization_text(locale)}

      configured?(env) and supported?(env) ->
        args = %{"event_id" => Ecto.UUID.generate(), "user_id" => user.id, "locale" => locale}
        Oban.insert!(Keyword.get(opts, :oban, Oban), Dawarich.Mail.TestEmailWorker.new(args))
        {:notice, text(locale, "test_email_queued", %{"email" => user.email})}

      true ->
        {:alert, text(locale, "smtp_not_configured", %{})}
    end
  rescue
    error in ArgumentError ->
      failure(
        ExploreFeatures.locale(Dawarich.UserSettings.get(user), ambient),
        "ArgumentError: " <> Exception.message(error)
      )

    _error ->
      failure(ExploreFeatures.locale(Dawarich.UserSettings.get(user), ambient), "IOError")
  catch
    _, _ -> failure(ExploreFeatures.locale(Dawarich.UserSettings.get(user), ambient), "IOError")
  end

  defp authorization_text(locale) do
    {:ok, message} =
      I18n.t(locale, "controllers.application.you_are_not_authorized_to_perform_this_action")

    message
  end

  defp failure(locale, detail),
    do: {:alert, text(locale, "test_email_failed", %{"error" => detail})}

  defp text(locale, key, bindings) do
    {:ok, text} = I18n.t(locale, "controllers.settings.general." <> key, bindings)
    text
  end
end
