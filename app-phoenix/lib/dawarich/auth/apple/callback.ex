defmodule Dawarich.Auth.Apple.Callback do
  @moduledoc false
  alias Dawarich.Auth.Apple.{Cookies, Verify}
  alias Dawarich.Auth.{SessionCookie, Providers.Accounts, Providers.Completion, Providers.Failure}
  alias DawarichWeb.AuthCookie

  def call(conn, params, context) do
    {conn, cookies} = Cookies.take(conn, context)
    env = Map.get_lazy(context, :env, &System.get_env/0)

    verification =
      context
      |> Map.put(:nonce, cookies["apple_oauth_nonce"])
      |> Map.put(:client_id, env["APPLE_WEB_SERVICES_ID"])

    cond do
      params["error"] == "user_cancelled_authorize" ->
        reject(conn, "sign_in_with_apple_was_cancelled", context, "notice")

      params["error"] not in [nil, ""] ->
        reject(conn, "did_not_complete", context)

      not state?(cookies["apple_oauth_state"], params["state"]) ->
        reject(conn, "state_mismatch", context)

      true ->
        case Verify.call(params["id_token"], verification) do
          {:ok, claims} ->
            resolve(conn, claims, params, context)

          _ ->
            Failure.redirect(
              conn,
              "/users/sign_in",
              "controllers.users.apple_oauth.sign_in_failed",
              %{"message" => "invalid token"},
              context
            )
        end
    end
  end

  defp resolve(conn, claims, params, context) do
    identity =
      Map.merge(
        %{
          provider: "apple",
          uid: claims["sub"],
          email: claims["email"],
          email_verified: claims["email_verified"] in [true, "true"],
          first_name: nil,
          last_name: nil
        },
        name(params["user"])
      )

    case Accounts.resolve(identity, Map.put(context, :on_email_collision, :raise_only)) do
      {:ok, user, created} ->
        Completion.complete(conn, user, created, "apple", context)

      {:link_required, link} ->
        pending = %{
          "user_id" => link.user.id,
          "provider" => "apple",
          "uid" => link.uid,
          "provider_label" => "Sign in with Apple",
          "expires_at" => epoch(context) + 900
        }

        session = Map.put(conn.assigns.rails_session, "pending_oauth_link", pending)

        conn
        |> AuthCookie.session(
          SessionCookie.for_form(
            session,
            Map.get_lazy(context, :secret, &Dawarich.RailsSecret.fetch/0)
          )
        )
        |> Failure.redirect_to("/auth/account_link/challenge")

      {:error, reason} ->
        key =
          case reason do
            :unverified_email -> "email_not_verified"
            :pending_deletion -> "account_pending_deletion"
            :missing_email -> "missing_email"
            _ -> "did_not_complete"
          end

        reject(conn, key, context)
    end
  end

  defp reject(conn, key, context, kind \\ "alert"),
    do:
      Failure.redirect(
        conn,
        "/users/sign_in",
        "controllers.users.apple_oauth." <> key,
        %{},
        context,
        kind
      )

  defp state?(expected, actual) when is_binary(expected) and expected != "" and is_binary(actual),
    do: Plug.Crypto.secure_compare(expected, actual)

  defp state?(_, _), do: false
  defp epoch(context), do: Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()

  defp name(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{"name" => name}} when is_map(name) ->
        %{first_name: name["firstName"], last_name: name["lastName"]}

      _ ->
        %{}
    end
  end

  defp name(_), do: %{}
end
