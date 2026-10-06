defmodule Dawarich.Auth.Providers.Failure do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Auth.{SessionCookie, Providers.Accounts}
  alias DawarichWeb.{AuthCookie, RequestURL, Translate}

  def respond(conn, reason, provider, context) do
    {path, key, bindings} =
      case reason do
        :invalid_credentials ->
          {"/", "invalid_credentials", %{}}

        :timeout ->
          {"/", "connection_timeout", %{}}

        :csrf_detected ->
          {"/", "security_error", %{}}

        :discovery ->
          {"/", "provider_unavailable", %{}}

        :provider_unavailable ->
          {"/", "provider_unavailable", %{}}

        :issuer_mismatch ->
          {"/", "provider_configuration_error", %{}}

        :configuration ->
          {"/", "provider_configuration_error", %{}}

        :registration_disabled ->
          {"/", "oidc_account_requires_administrator", %{}}

        :account_creation_failed ->
          {"/", "account_creation_failed", %{}}

        :unverified_email ->
          {"/users/sign_in", "email_not_verified",
           %{"provider" => Accounts.label(provider, context)}}

        :pending_deletion ->
          {"/users/sign_in", "account_pending_deletion", %{}}

        _ ->
          {"/", "authentication_failed", %{"detail" => safe_detail(reason)}}
      end

    redirect(conn, path, "controllers.users.omniauth_callbacks." <> key, bindings, context)
  end

  def redirect(conn, path, key, bindings, context, kind \\ "alert") do
    locale = Map.get(context, :locale, "en")
    text = Translate.t(locale, key, bindings)

    session =
      Map.put(conn.assigns[:rails_session] || %{}, "flash", %{
        "discard" => [],
        "flashes" => %{kind => text}
      })

    conn
    |> AuthCookie.session(
      SessionCookie.for_form(
        session,
        Map.get_lazy(context, :secret, &Dawarich.RailsSecret.fetch/0)
      )
    )
    |> redirect_to(path)
  rescue
    _ -> terminal(conn)
  end

  def redirect_to(conn, path) do
    conn
    |> DawarichWeb.RailsHeaders.call([])
    |> put_resp_header("x-dawarich-auth-owner", "native-provider")
    |> put_resp_header(
      "location",
      if(String.starts_with?(path, "/"), do: RequestURL.base(conn) <> path, else: path)
    )
    |> send_resp(302, "")
    |> halt()
  end

  def terminal(conn), do: conn |> send_resp(503, "Authentication unavailable") |> halt()
  defp safe_detail(:access_denied), do: "access_denied"
  defp safe_detail(_), do: "Unknown error"

  def link_error(conn, :locked, context),
    do: redirect(conn, "/users/sign_in", "devise.failure.locked", %{}, context)

  def link_error(conn, reason, context) do
    key =
      case reason do
        :replayed -> "this_link_has_already_been_used"
        :different_identity -> "already_linked_to_different_identity"
        :no_pending_link -> "no_pending_account_link"
        :too_many_attempts -> "too_many_invalid_attempts_start_the_linking_flow_again"
        :rate_limited -> "account_link_rate_limited"
        _ -> "link_invalid_or_expired"
      end

    redirect(
      conn,
      "/users/sign_in",
      "controllers.auth.account_links." <> key,
      %{"provider" => "OAuth"},
      context
    )
  end
end
