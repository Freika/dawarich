defmodule Dawarich.Auth.Providers.Github do
  @moduledoc false
  alias Dawarich.Auth.Providers.{Jwks, State}

  def authorize(config, session) do
    {state, session} = State.start(session)

    params = %{
      client_id: config.client_id,
      redirect_uri: config.redirect_uri,
      response_type: "code",
      scope: config.scope,
      state: state
    }

    {:ok, config.authorization_endpoint <> "?" <> URI.encode_query(params), session}
  end

  def callback(_config, %{"error" => _}, _pending, _context), do: {:error, :access_denied}

  def callback(config, params, _pending, context) do
    exchange = %{
      client_id: config.client_id,
      client_secret: config.client_secret,
      redirect_uri: config.redirect_uri,
      code: params["code"],
      grant_type: "authorization_code"
    }

    with code when is_binary(code) and code != "" <- params["code"],
         {:ok, %{"access_token" => token}} when is_binary(token) <-
           Jwks.request(:post, config.token_endpoint, exchange, [], context),
         headers = [{"authorization", "Bearer " <> token}],
         {:ok, profile} when is_map(profile) <-
           Jwks.request(:get, config.userinfo_endpoint, %{}, headers, context),
         {:ok, emails} when is_list(emails) <-
           Jwks.request(:get, config.emails_endpoint, %{}, headers, context) do
      primary =
        Enum.find(
          emails,
          &(&1["primary"] not in [nil, false] and &1["verified"] not in [nil, false])
        )

      email = primary && primary["email"]
      [first | rest] = String.split(profile["name"] || "", " ", parts: 2)

      {:ok,
       %{
         provider: "github",
         uid: to_string(profile["id"] || ""),
         email: email,
         email_verified: is_binary(email) and email != "",
         first_name: first,
         last_name: List.first(rest)
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_credentials}
    end
  end
end
