defmodule Dawarich.Mail.ExploreFeatures do
  @moduledoc false
  require EEx
  alias Dawarich.Mail.Layout

  @dir Path.expand("../../../priv/mail", __DIR__)
  @escapes %{"&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;", "'" => "&#39;"}

  for file <- ~w(explore_features.html explore_features.text) do
    @external_resource Path.join(@dir, file <> ".eex")
  end

  EEx.function_from_file(:defp, :html_body, Path.join(@dir, "explore_features.html.eex"), [
    :t,
    :h,
    :email
  ])

  EEx.function_from_file(:defp, :text_body, Path.join(@dir, "explore_features.text.eex"), [
    :t,
    :h,
    :email
  ])

  def message(recipient, fallback_locale, env) do
    locale = locale(Dawarich.UserSettings.get(recipient), fallback_locale)
    Map.merge(render(recipient.email, locale), %{from: env["SMTP_FROM"], to: recipient.email})
  end

  def render(email, locale) do
    html_t = fn key -> h(text!(locale, "users_mailer.explore_features." <> key)) end
    text_t = fn key -> text!(locale, "users_mailer.explore_features." <> key) end

    %{
      subject: text!(locale, "mailers.users.explore_features.subject"),
      html: Layout.html(locale, html_body(html_t, &h/1, email)),
      text: Layout.text(text_body(text_t, &h/1, email))
    }
  end

  def locale(settings, fallback) do
    available = Dawarich.I18n.available_locales()
    preferred = preferred(Dawarich.UserSettings.safe(settings))
    fallback = normalized_locale(fallback)

    cond do
      preferred in available -> preferred
      fallback in available -> fallback
      true -> "en"
    end
  end

  def h(text), do: String.replace(to_string(text), Map.keys(@escapes), &Map.fetch!(@escapes, &1))

  defp preferred(%{"locale" => value}), do: normalized_locale(value)

  defp preferred(_settings), do: nil

  defp normalized_locale(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalized_locale(_value), do: nil

  defp text!(locale, key) do
    case Dawarich.I18n.t(locale, key) do
      {:ok, text} when is_binary(text) -> text
      other -> raise "no translation for #{locale}.#{key}: #{inspect(other)}"
    end
  end
end
