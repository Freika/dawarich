defmodule Dawarich.Auth.Apple.Verify do
  @moduledoc false
  alias Dawarich.Auth.Providers.Jwks
  alias Dawarich.Auth.Recovery.Token

  def call(token, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)
    audience = Map.get(context, :client_id, env["APPLE_BUNDLE_ID"])
    uri = Map.get(context, :jwks_uri, "https://appleid.apple.com/auth/keys")

    with false <- Token.blank?(audience),
         {:ok, claims} <- Jwks.verify(token, uri, Map.put(context, :algorithms, ["RS256"])),
         true <- claims["iss"] == "https://appleid.apple.com",
         true <- claims["aud"] == audience,
         true <- is_number(claims["exp"]) and claims["exp"] > now(context),
         true <- is_number(claims["iat"]) and claims["iat"] <= now(context),
         true <- not_before?(claims["nbf"], context),
         true <- is_binary(claims["sub"]) and claims["sub"] != "",
         true <- nonce?(claims["nonce"], context[:nonce]) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  defp nonce?(actual, expected) do
    if Token.blank?(expected) do
      true
    else
      hash = :crypto.hash(:sha256, expected) |> Base.encode16(case: :lower)
      is_binary(actual) and Plug.Crypto.secure_compare(actual, hash)
    end
  end

  defp not_before?(nil, _), do: true
  defp not_before?(value, context) when is_number(value), do: value <= now(context) + 60
  defp not_before?(_, _), do: false
  defp now(context), do: Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
end
