defmodule Dawarich.Auth.Apple.Request do
  @moduledoc false
  alias Dawarich.Auth.Apple.Cookies
  alias Dawarich.Auth.Providers.Failure

  def enabled?(context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)

    context[:self_hosted] == false and
      Enum.all?(
        ~w(APPLE_WEB_SERVICES_ID APPLE_WEB_TEAM_ID APPLE_WEB_KEY_ID APPLE_WEB_P8_BASE64 APPLE_WEB_REDIRECT_URI),
        fn key ->
          is_binary(env[key]) and String.trim(env[key]) != ""
        end
      )
  end

  def call(conn, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)
    nonce = random()
    state = random()

    conn =
      conn
      |> Cookies.put("apple_oauth_nonce", nonce, context)
      |> Cookies.put("apple_oauth_state", state, context)

    ticket = conn.assigns.rails_session["pending_import_ticket"]

    conn =
      if is_binary(ticket) and ticket != "",
        do: Cookies.put(conn, "apple_pending_import_ticket", ticket, context),
        else: conn

    query =
      URI.encode_query(%{
        client_id: env["APPLE_WEB_SERVICES_ID"],
        redirect_uri: env["APPLE_WEB_REDIRECT_URI"],
        response_type: "code id_token",
        response_mode: "form_post",
        scope: "name email",
        state: state,
        nonce: Base.encode16(:crypto.hash(:sha256, nonce), case: :lower)
      })

    Failure.redirect_to(conn, "https://appleid.apple.com/auth/authorize?" <> query)
  end

  defp random, do: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
end
