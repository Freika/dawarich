defmodule Dawarich.Auth.Providers.Google do
  @moduledoc false
  alias Dawarich.Auth.Providers.{Jwks, State}

  def authorize(config, session) do
    {state, session} = State.start(session)

    params = %{
      client_id: config.client_id,
      redirect_uri: config.redirect_uri,
      response_type: "code",
      scope:
        "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile",
      state: state,
      access_type: "offline"
    }

    {:ok, config.authorization_endpoint <> "?" <> URI.encode_query(params), session}
  end

  def verify_id_token(token, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)

    audiences =
      Map.get(
        context,
        :audiences,
        Enum.reject(
          [
            env["GOOGLE_IOS_CLIENT_ID"],
            env["GOOGLE_ANDROID_CLIENT_ID"],
            env["GOOGLE_OAUTH_CLIENT_ID"]
          ],
          &is_nil/1
        )
      )

    uri = Map.get(context, :jwks_uri, "https://www.googleapis.com/oauth2/v3/certs")

    with {:ok, claims} <- Jwks.verify(token, uri, Map.put(context, :algorithms, ["RS256"])),
         true <- claims["iss"] in ["accounts.google.com", "https://accounts.google.com"],
         true <- claims["aud"] in audiences,
         true <- is_number(claims["exp"]) and claims["exp"] > now(context),
         true <- not_before?(claims["nbf"], context),
         true <- is_binary(claims["sub"]) and claims["sub"] != "",
         true <- nonce?(claims["nonce"], context[:nonce]) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  def callback(_config, %{"error" => _}, _pending, _context), do: {:error, :access_denied}

  def callback(config, params, pending, context) do
    exchange = %{
      client_id: config.client_id,
      client_secret: config.client_secret,
      redirect_uri: config.redirect_uri,
      code: params["code"],
      grant_type: "authorization_code"
    }

    with code when is_binary(code) and code != "" <- params["code"],
         {:ok, %{"access_token" => token} = tokens} when is_binary(token) <-
           Jwks.request(:post, config.token_endpoint, exchange, [], context),
         {:ok, profile} <- profile(tokens, token, config, pending, context) do
      {:ok, identity(profile)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_credentials}
    end
  end

  defp profile(tokens, token, config, pending, context) do
    verification =
      context |> Map.put(:audiences, [config.client_id]) |> Map.put(:nonce, pending.nonce)

    verification =
      Map.put(
        verification,
        :jwks_uri,
        Map.get(config, :jwks_uri, "https://www.googleapis.com/oauth2/v3/certs")
      )

    case tokens["id_token"] do
      absent when absent in [nil, ""] ->
        Jwks.request(
          :get,
          config.userinfo_endpoint,
          %{},
          [{"authorization", "Bearer " <> token}],
          context
        )

      id_token ->
        verify_id_token(id_token, verification)
    end
  end

  def identity(profile) do
    email = if profile["email_verified"] not in [nil, false], do: profile["email"]

    %{
      provider: "google_oauth2",
      uid: to_string(profile["sub"] || ""),
      email: email,
      email_verified: profile["email_verified"] == true,
      first_name: profile["given_name"],
      last_name: profile["family_name"]
    }
  end

  defp not_before?(nil, _context), do: true
  defp not_before?(value, context) when is_number(value), do: value <= now(context) + 60
  defp not_before?(_, _context), do: false

  defp nonce?(_, nil), do: true
  defp nonce?(_, ""), do: true

  defp nonce?(actual, expected) when is_binary(actual) and is_binary(expected),
    do: Plug.Crypto.secure_compare(actual, expected)

  defp nonce?(_, _), do: false
  defp now(context), do: Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
end
