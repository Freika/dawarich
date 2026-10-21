defmodule DawarichWeb.SettingsLive.GeneralHelpers do
  @moduledoc false

  import DawarichWeb.Translate, only: [t: 3]

  def flag_code(code) do
    case Dawarich.I18n.t(code, "language_flag", %{}, fallback: false) do
      {:ok, flag} -> flag
      _ -> nil
    end
  end

  def native_name(code) do
    case Dawarich.I18n.t(code, "language_name", %{}, fallback: false) do
      {:ok, name} -> name
      _ -> String.upcase(code)
    end
  end

  def smtp_link(locale) do
    text =
      locale
      |> t("controllers.settings.general.smtp_not_configured_link", %{})
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    {:safe,
     ~s(<a target="_blank" rel="noopener" class="link link-primary" href="https://dawarich.app/docs/self-hosting/configuration/smtp/">#{text}</a>)}
  end

  def platform_name(platform) when is_binary(platform),
    do:
      platform
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  def platform_name(_platform), do: ""
end
