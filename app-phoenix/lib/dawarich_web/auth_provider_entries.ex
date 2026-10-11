defmodule DawarichWeb.AuthProviderEntries do
  @moduledoc false
  alias DawarichWeb.{RailsCsrf, Translate}

  def for_request(conn, env \\ System.get_env()) do
    hosted = Dawarich.ReleaseMigration.self_hosted?(env)

    mobile =
      Enum.any?(
        Plug.Conn.get_req_header(conn, "user-agent"),
        &Regex.match?(~r/iPhone|iPad|iPod|Android/i, &1)
      )

    oidc =
      present?(env, "OIDC_CLIENT_ID") and
        (present?(env, "OIDC_CLIENT_SECRET") or
           String.downcase(String.trim(env["OIDC_PKCE_ENABLED"] || "")) == "true")

    locale = conn.assigns[:locale] || "en"

    specs =
      if hosted do
        if oidc,
          do: [
            {"openid_connect", "POST",
             Translate.t(locale, "oauth_providers.sign_in_with_provider", %{
               "provider" => env["OIDC_PROVIDER_NAME"] || "Openid Connect"
             })}
          ],
          else: []
      else
        for {provider, prefix} <- [{"github", "GITHUB"}, {"google_oauth2", "GOOGLE"}],
            present?(env, prefix <> "_OAUTH_CLIENT_ID") and
              present?(env, prefix <> "_OAUTH_CLIENT_SECRET"),
            provider != "google_oauth2" or not mobile,
            do:
              {provider, "POST",
               Translate.t(
                 locale,
                 "oauth_providers.sign_in_with_" <>
                   if(provider == "google_oauth2", do: "google", else: provider),
                 %{}
               )}
      end

    specs =
      if not mobile and Dawarich.Auth.Apple.Request.enabled?(%{self_hosted: hosted, env: env}),
        do:
          specs ++
            [{"apple", "GET", Translate.t(locale, "oauth_providers.sign_in_with_apple", %{})}],
        else: specs

    providers =
      for {provider, method, label} <- specs do
        action = if provider == "apple", do: "/users/auth/apple", else: "/users/auth/" <> provider

        %{
          action: action,
          method: method,
          label: label,
          csrf:
            if(method == "POST",
              do: RailsCsrf.masked_form_token(conn.assigns.rails_session, action, method)
            )
        }
      end

    %{
      email_password: email_password_enabled?(env),
      providers: providers
    }
  end

  def email_password_enabled?(env \\ System.get_env()) do
    oidc =
      present?(env, "OIDC_CLIENT_ID") and
        (present?(env, "OIDC_CLIENT_SECRET") or
           String.downcase(String.trim(env["OIDC_PKCE_ENABLED"] || "")) == "true")

    not (Dawarich.ReleaseMigration.self_hosted?(env) and oidc) or
      Map.get(env, "ALLOW_EMAIL_PASSWORD_LOGIN", "true") == "true"
  end

  defp present?(env, key), do: String.trim(env[key] || "") != ""
end
