defmodule Dawarich.Auth.Providers.OidcDiscovery do
  @moduledoc false
  alias Dawarich.Auth.Providers.Jwks

  def configuration(env, context) do
    pkce = String.downcase(String.trim(env["OIDC_PKCE_ENABLED"] || "")) == "true"
    id = env["OIDC_CLIENT_ID"]
    secret = env["OIDC_CLIENT_SECRET"]
    issuer = normalize(env["OIDC_ISSUER"] || "")

    discovery =
      issuer != "" and String.downcase(String.trim(env["OIDC_DISCOVERY"] || "")) != "false"

    if present?(id) and (present?(secret) or pkce) do
      config = %{
        client_id: id,
        client_secret: secret,
        issuer: if(issuer == "", do: nil, else: issuer),
        redirect_uri:
          env["OIDC_REDIRECT_URI"] ||
            (env["APPLICATION_URL"] || "http://localhost:3000") <>
              "/users/auth/openid_connect/callback",
        pkce: pkce,
        client_auth_method: if(present?(secret), do: :basic, else: :none),
        scope: "openid email profile"
      }

      if discovery, do: discover(config, context), else: manual(config, env)
    else
      {:error, :configuration}
    end
  end

  def normalize(value) do
    [base | fragment] = String.split(String.trim(value), "#", parts: 2)

    normalized =
      base |> String.trim() |> String.replace(~r{/\.well-known/openid-configuration/?$}, "")

    if Enum.any?(fragment, &String.starts_with?(&1, [".well-known", "/.well-known"])),
      do: String.replace(normalized, ~r{^(https?://[^/]+)/$}, "\\1"),
      else: normalized
  end

  defp discover(config, context) do
    with true <- url?(config.issuer),
         {:ok, metadata} when is_map(metadata) <-
           Jwks.request(
             :get,
             config.issuer <> "/.well-known/openid-configuration",
             %{},
             [],
             context
           ),
         true <- metadata["issuer"] == config.issuer,
         true <-
           Enum.all?(
             ~w(authorization_endpoint token_endpoint userinfo_endpoint jwks_uri),
             &url?(metadata[&1])
           ) do
      {:ok,
       Map.merge(config, %{
         authorization_endpoint: metadata["authorization_endpoint"],
         token_endpoint: metadata["token_endpoint"],
         userinfo_endpoint: metadata["userinfo_endpoint"],
         jwks_uri: metadata["jwks_uri"]
       })}
    else
      false -> {:error, :issuer_mismatch}
      _ -> {:error, :discovery}
    end
  end

  defp manual(config, env) do
    scheme = env["OIDC_SCHEME"] || "https"
    default = if String.downcase(scheme) == "http", do: 80, else: 443

    port =
      case Integer.parse(String.trim(env["OIDC_PORT"] || "")) do
        {n, ""} when n in 1..65535 -> n
        _ -> default
      end

    base = URI.to_string(%URI{scheme: scheme, host: env["OIDC_HOST"], port: port})

    if present?(env["OIDC_HOST"]) and url?(base) do
      {:ok,
       Map.merge(config, %{
         authorization_endpoint:
           endpoint(base, env["OIDC_AUTHORIZATION_ENDPOINT"] || "/authorize"),
         token_endpoint: endpoint(base, env["OIDC_TOKEN_ENDPOINT"] || "/token"),
         userinfo_endpoint: endpoint(base, env["OIDC_USERINFO_ENDPOINT"] || "/userinfo"),
         jwks_uri: env["OIDC_JWKS_URI"]
       })}
    else
      {:error, :configuration}
    end
  end

  defp endpoint(base, "/" <> _ = path), do: base <> path
  defp endpoint(_base, url), do: url
  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp url?(value) when is_binary(value) do
    uri = URI.parse(value)

    uri.scheme in ["http", "https"] and present?(uri.host) and is_nil(uri.userinfo) and
      is_nil(uri.fragment)
  end

  defp url?(_), do: false
end
