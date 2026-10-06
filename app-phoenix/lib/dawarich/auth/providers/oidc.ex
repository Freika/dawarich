defmodule Dawarich.Auth.Providers.Oidc do
  @moduledoc false
  alias Dawarich.Auth.Providers.{Jwks, OidcClaims, OidcDiscovery, Pkce, State}
  def configuration(env, context), do: OidcDiscovery.configuration(env, context)

  def authorize(config, session) do
    {state, session} = State.start(session, true)
    {pkce, session} = if config.pkce, do: Pkce.authorize(session), else: {%{}, session}

    params =
      %{
        client_id: config.client_id,
        redirect_uri: config.redirect_uri,
        scope: config.scope,
        response_type: "code",
        state: state,
        nonce: session["omniauth.nonce"]
      }
      |> Map.merge(pkce)

    {:ok, config.authorization_endpoint <> "?" <> URI.encode_query(params), session}
  end

  def callback(_config, %{"error" => _}, _pending, _context), do: {:error, :access_denied}

  def callback(config, params, pending, context) do
    exchange = %{
      client_id: config.client_id,
      redirect_uri: config.redirect_uri,
      code: params["code"],
      grant_type: "authorization_code",
      scope: config.scope
    }

    exchange = if config.pkce, do: Map.merge(exchange, Pkce.exchange(pending)), else: exchange

    headers =
      if config.client_auth_method == :basic do
        [
          {"authorization",
           "Basic " <>
             Base.encode64(
               URI.encode_www_form(config.client_id) <>
                 ":" <> URI.encode_www_form(config.client_secret)
             )}
        ]
      else
        []
      end

    with code when is_binary(code) and code != "" <- params["code"],
         {:ok, %{"access_token" => token} = tokens} when is_binary(token) <-
           Jwks.request(:post, config.token_endpoint, exchange, headers, context),
         {:ok, claims} <-
           verified(tokens["id_token"], config, params["nonce"] || pending.nonce, context),
         {:ok, profile} when is_map(profile) <-
           Jwks.request(
             :get,
             config.userinfo_endpoint,
             %{},
             [{"authorization", "Bearer " <> token}],
             context
           ) do
      {:ok, OidcClaims.identity(Map.merge(profile, claims))}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_credentials}
    end
  end

  defp verified(nil, _, _, _), do: {:ok, %{}}

  defp verified(token, config, nonce, context),
    do: OidcClaims.verify(token, config, nonce, context)
end
